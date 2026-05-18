local M = {}
local uv = vim.uv or vim.loop

local DEFAULT_SKIP = { [".git"] = true, ["node_modules"] = true, ["bin"] = true, ["obj"] = true }

local function join(a, b)
  if a:sub(-1) == "/" then return a .. b end
  return a .. "/" .. b
end

---Recursively scan `root` for files whose name matches the Lua pattern `match`.
---`depth` matches plenary semantics: 1 = root only, 2 = one level of subdirs, etc.
---@param root string
---@param opts { match: string, depth?: integer, skip?: table<string, boolean>, on_done: fun(paths: string[]) }
function M.find_async(root, opts)
  local match = assert(opts.match, "fs.find_async: missing match")
  local depth = opts.depth or math.huge
  local skip = opts.skip or DEFAULT_SKIP
  local on_done = assert(opts.on_done, "fs.find_async: missing on_done")

  local results = {}
  local pending = 0
  local finished = false

  local function finalize()
    if finished then return end
    finished = true
    vim.schedule(function() on_done(results) end)
  end

  local function scan(dir, level)
    pending = pending + 1
    uv.fs_opendir(dir, function(err, handle)
      if err or not handle then
        pending = pending - 1
        if pending == 0 then finalize() end
        return
      end

      local function read_more()
        uv.fs_readdir(handle, function(rerr, entries)
          if rerr or not entries then
            uv.fs_closedir(handle, function() end)
            pending = pending - 1
            if pending == 0 then finalize() end
            return
          end

          for _, entry in ipairs(entries) do
            local full = join(dir, entry.name)
            if entry.type == "directory" then
              if level < depth and not skip[entry.name] then scan(full, level + 1) end
            elseif entry.type == "file" then
              if entry.name:match(match) then table.insert(results, full) end
            end
          end
          read_more()
        end)
      end

      read_more()
    end, 64)
  end

  scan(root, 1)
end

---List files in a single directory (non-recursive) that match any pattern.
---@param dir string
---@param patterns string[]
---@param cb fun(paths: string[])
local function list_dir_matches(dir, patterns, cb)
  local matches = {}
  uv.fs_opendir(dir, function(err, handle)
    if err or not handle then return cb(matches) end
    local function read_more()
      uv.fs_readdir(handle, function(rerr, entries)
        if rerr or not entries then
          uv.fs_closedir(handle, function() end)
          return cb(matches)
        end
        for _, entry in ipairs(entries) do
          if entry.type == "file" then
            for _, p in ipairs(patterns) do
              if entry.name:match(p) then
                table.insert(matches, join(dir, entry.name))
                break
              end
            end
          end
        end
        read_more()
      end)
    end
    read_more()
  end, 64)
end

---Walk parent directories starting at `start_dir`, returning the first file
---matching any pattern. Async.
---@param start_dir string
---@param opts { patterns: string[], on_done: fun(path: string?) }
function M.find_upward_first_async(start_dir, opts)
  local patterns = opts.patterns
  local on_done = opts.on_done

  local function visit(dir)
    list_dir_matches(dir, patterns, function(matches)
      if #matches > 0 then return vim.schedule(function() on_done(matches[1]) end) end
      local parent = vim.fs.dirname(dir)
      if not parent or parent == dir then return vim.schedule(function() on_done(nil) end) end
      visit(parent)
    end)
  end

  visit(start_dir)
end

---Walk parent directories from `start_dir` up to (and including) `stop_at`,
---collecting every file matching any pattern. Async.
---@param start_dir string
---@param opts { patterns: string[], stop_at?: string, on_done: fun(paths: string[]) }
function M.find_upward_collect_async(start_dir, opts)
  local patterns = opts.patterns
  local stop_at = opts.stop_at and vim.fs.normalize(opts.stop_at) or nil
  local on_done = opts.on_done

  local results = {}

  local function visit(dir)
    list_dir_matches(dir, patterns, function(matches)
      for _, m in ipairs(matches) do
        table.insert(results, m)
      end
      local at_stop = stop_at and vim.fs.normalize(dir) == stop_at
      local parent = vim.fs.dirname(dir)
      if at_stop or not parent or parent == dir then return vim.schedule(function() on_done(results) end) end
      visit(parent)
    end)
  end

  visit(start_dir)
end

return M
