local M = {
  client_roots = {},
  watchers = {},
}

local function is_absolute(path) return path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil end

local function resolve_relative_path(base_dir, path)
  if is_absolute(path) then return vim.fs.normalize(path) end
  return vim.fs.normalize(vim.fs.joinpath(base_dir, path))
end

local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  return table.concat(lines, "\n")
end

local function find_git_dir(root_dir)
  local dir = vim.fs.normalize(root_dir)

  while dir and dir ~= "" do
    local git_path = vim.fs.joinpath(dir, ".git")
    local stat = vim.uv.fs_stat(git_path)

    if stat and stat.type == "directory" then return vim.fs.normalize(git_path) end

    if stat and stat.type == "file" then
      local git_dir = read_file(git_path)
      git_dir = git_dir and git_dir:match("^gitdir:%s*(.-)%s*$")
      if git_dir and git_dir ~= "" then return resolve_relative_path(dir, git_dir) end
    end

    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then return nil end
    dir = parent
  end

  return nil
end

local function git_head_state(git_dir)
  local head_path = vim.fs.joinpath(git_dir, "HEAD")
  return {
    head_path = head_path,
    fingerprint = read_file(head_path),
  }
end

function M.close(root_dir)
  local state = M.watchers[root_dir]
  if not state then return end

  if state.timer then
    state.timer:stop()
    state.timer:close()
  end

  for _, watcher in ipairs(state.watchers or {}) do
    watcher:stop()
    watcher:close()
  end

  M.watchers[root_dir] = nil
end

local function watch_git_path(watchers, path, on_change)
  if not path or vim.uv.fs_stat(path) == nil then return end

  local watcher = vim.uv.new_fs_event()
  if not watcher then return end

  local ok = watcher:start(path, {}, function() vim.schedule(on_change) end)
  if ok then
    table.insert(watchers, watcher)
  else
    watcher:close()
  end
end

---@param client vim.lsp.Client
---@param opts easy-dotnet.LspOpts
---@param on_changed fun(root_dir: string)
function M.register(client, opts, on_changed)
  if opts.restart_roslyn_on_branch_change ~= true then return end

  local root_dir = client.root_dir
  M.client_roots[client.id] = root_dir
  if not root_dir or M.watchers[root_dir] then return end

  local git_dir = find_git_dir(root_dir)
  if not git_dir then return end

  local state = git_head_state(git_dir)
  if not state.fingerprint then return end

  local watcher_state = {
    fingerprint = state.fingerprint,
    watchers = {},
    timer = vim.uv.new_timer(),
  }

  if not watcher_state.timer then return end

  local function schedule_restart()
    watcher_state.timer:stop()
    watcher_state.timer:start(
      300,
      0,
      vim.schedule_wrap(function()
        local next_state = git_head_state(git_dir)
        if next_state.fingerprint == watcher_state.fingerprint then return end

        M.close(root_dir)
        on_changed(root_dir)
      end)
    )
  end

  watch_git_path(watcher_state.watchers, state.head_path, schedule_restart)

  if #watcher_state.watchers == 0 then
    watcher_state.timer:close()
    return
  end

  M.watchers[root_dir] = watcher_state
end

---@param client_id integer
---@param has_client_for_root fun(root_dir: string): boolean
function M.unregister_client(client_id, has_client_for_root)
  local root_dir = M.client_roots[client_id]
  M.client_roots[client_id] = nil
  if not root_dir then return end

  vim.schedule(function()
    if not has_client_for_root(root_dir) then M.close(root_dir) end
  end)
end

return M
