local M = {}

---@param prompt string search term
---@param client DotnetClient rpc client
local function nuget_search_rpc(prompt, client)
  local co = coroutine.running()
  assert(co, "nuget_search_yielding must be called inside a coroutine")

  local results = {}

  client:nuget_search(prompt, nil, function(p)
    for _, r in ipairs(p) do
      table.insert(results, { id = r.id, display = r.id .. " (" .. r.source .. ")" })
    end
    vim.schedule(function() coroutine.resume(co, results) end)
  end)

  return coroutine.yield()
end

M.nuget_search = function()
  local co = coroutine.running()
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local results = {}
  client:initialize(function()
    require("fzf-lua").fzf_live(function(prompt)
      return function(add_item, finished)
        local res = nuget_search_rpc(prompt, client)
        results = res
        for _, r in ipairs(res) do
          add_item(r.display)
        end
        finished()
      end
    end, {
      actions = {
        ["default"] = function(selected)
          for _, value in ipairs(results) do
            if value.display == selected[1] then
              coroutine.resume(co, value.id)
              return
            end
          end
        end,
      },
    })
  end)
  return coroutine.yield()
end

M.migration_picker = function(opts, migration)
  local entry_maker = opts.entry_maker
    or function(entry)
      return {
        display = entry.display or tostring(entry),
        value = entry,
        ordinal = entry.display or tostring(entry),
      }
    end

  local fzf_options = {}
  local fzf_entries = {}
  for _, entry in ipairs(migration) do
    local item = entry_maker(entry)
    table.insert(fzf_options, item.display)
    table.insert(fzf_entries, item)
  end

  require("fzf-lua").fzf_exec(fzf_options, {
    prompt = "Migrations" .. " > ",
    on_select = function(selected_entry)
      local selected_value = nil
      for _, item in ipairs(fzf_entries) do
        if item.display == selected_entry then
          selected_value = item
          break
        end
      end
      if selected_value then opts.on_select(selected_value.value) end
    end,
  })
end

--- Generates a secret preview for fzf-lua
---@param entry table
---@param get_secret_path function
---@param readFile function
---@return table
local function secrets_preview(entry, get_secret_path, readFile)
  if not entry or not entry.secrets then return { "Secrets file does not exist", "<CR> to create" } end
  local content = readFile(get_secret_path(entry.secrets))
  if content ~= nil then
    return content
  else
    return { "Secrets file could not be read" }
  end
end

M.preview_picker = function(_, options, on_select_cb, title, get_secret_path, readFile)
  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local entries = {}
  local metadata = {}
  for _, option in ipairs(options) do
    if not option.display or not option.path then error("Invalid entry detected") end
    table.insert(entries, option.display)
    metadata[option.display] = {
      secrets = option.secrets,
      path = option.path,
      runnable = option.runnable,
    }
  end

  -- Define the preview function for fzf-lua
  local preview_fn = function(entry)
    local display_name = entry[1]
    if not display_name or display_name == "" then return { "Invalid entry display" } end
    local entry_data = metadata[display_name]
    if entry_data == nil then return { "No metadata found for entry" } end
    return secrets_preview(entry_data, get_secret_path, readFile)
  end

  require("fzf-lua").fzf_exec(entries, {
    prompt = title .. "> ",
    preview = preview_fn,
    actions = {
      ["default"] = function(selected)
        local entry_meta = metadata[selected[1]]
        if entry_meta == nil then return end
        on_select_cb(entry_meta)
      end,
    },
  })
end

M.picker = function(_, options, on_select_cb, title, autopick, apply_numeration)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local fzf_options = {}
  for index, option in ipairs(options) do
    local display_text = option.display
    if apply_numeration then display_text = index .. ". " .. option.display end
    table.insert(fzf_options, display_text)
  end

  require("fzf-lua").fzf_exec(fzf_options, {
    prompt = (title or "Select an option") .. " > ",

    actions = {
      ["default"] = function(selected)
        local selected_value = nil
        for i, display_text in ipairs(fzf_options) do
          if display_text == selected[1] then
            selected_value = options[i]
            break
          end
        end
        if selected_value then on_select_cb(selected_value) end
      end,
    },
  })
end

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param title string | nil
---@param autopick boolean
---@param apply_numeration boolean
---@return T
M.pick_sync = function(bufnr, options, title, autopick, apply_numeration)
  local co = coroutine.running()
  local selected = nil
  M.picker(bufnr, options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick, apply_numeration)
  if not selected then coroutine.yield() end
  return selected
end

return M
