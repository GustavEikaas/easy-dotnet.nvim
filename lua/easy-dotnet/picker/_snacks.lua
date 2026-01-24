local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local M = {}

local function find_nuget_packages(_, ctx)
  local Async = require("snacks.picker.util.async")
  ---@async
  return function(cb)
    local self = Async.running()
    local aborted = false
    local handle = nil

    self:on("abort", function()
      aborted = true
      cb = function() end
      if handle and handle.cancel then pcall(handle.cancel, handle) end
    end)

    client:initialize(function()
      if aborted then return end

      local query = (ctx.filter and ctx.filter.search) or ""
      handle = client.nuget:nuget_search(query, nil, function(res)
        if aborted then return end

        if not res or type(res) ~= "table" or vim.tbl_isempty(res) then
          self:resume()
          return
        end

        for _, pkg in ipairs(res) do
          ---@type easy-dotnet.Nuget.PackageMetadata
          cb({ text = pkg.id or "(unknown id)" })
        end

        self:resume()
      end)
    end)

    self:suspend()
  end
end

M.nuget_search = function()
  local selected = nil
  local co = coroutine.running()

  require("snacks").picker.pick(nil, {
    title = "NuGet Search",
    live = true,
    layout = "select",
    format = "text",
    finder = find_nuget_packages,
    confirm = function(picker, item)
      picker:close()
      selected = item.text
      if coroutine.status(co) ~= "running" then coroutine.resume(co) end
    end,
  })

  if not selected then coroutine.yield() end
  return selected
end

M.migration_picker = function(opts, migrations)
  local picker_items = {}
  for _, migration in ipairs(migrations) do
    table.insert(picker_items, {
      text = migration,
      file = opts.entry_maker(migration).path,
    })
  end

  require("snacks").picker.pick(nil, {
    items = picker_items,
    format = "text",
    preview = "file",
    title = "Migrations",
  })
end

local function get_preview_text(option, get_secret_path, read_file)
  if not option or not option.secrets then return "Secrets file does not exist\n<CR> to create" end
  local content = read_file(get_secret_path(option.secrets))
  if content ~= nil then
    return table.concat(content, "\n")
  else
    return "Secrets file could not be read"
  end
end

---@generic T
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param get_secret_path function
---@param read_content function
M.preview_picker = function(options, on_select_cb, title, get_secret_path, read_content)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local picker_items = {}
  for _, option in ipairs(options) do
    table.insert(picker_items, {
      text = option.display,
      option = option,
      preview = {
        text = get_preview_text(option, get_secret_path, read_content),
        ft = "json",
      },
    })
  end

  require("snacks").picker.pick(nil, {
    items = picker_items,
    format = "text",
    preview = "preview",
    title = title,
    confirm = function(picker, item)
      picker:close()
      on_select_cb(item.option)
    end,
  })
end

---@generic T
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param autopick boolean
---@param apply_numeration boolean
M.picker = function(options, on_select_cb, title, autopick, apply_numeration)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local picker_items = {}
  for index, option in ipairs(options) do
    local display_text = option.display
    if apply_numeration then display_text = index .. ". " .. option.display end
    table.insert(picker_items, { text = display_text, option = option })
  end

  require("snacks").picker.pick(nil, {
    items = picker_items,
    format = "text",
    title = title,
    layout = "select",
    confirm = function(picker, item)
      picker:close()
      on_select_cb(item.option)
    end,
  })
end

-- (options, on_select_cb, title, apply_numeration)
M.multi_picker = function() error("multi_picker not implemented for snacks") end

---@generic T
---@param options table<T>
---@param title string | nil
---@param autopick boolean
---@param apply_numeration boolean
---@return T
M.pick_sync = function(options, title, autopick, apply_numeration)
  local co = coroutine.running()
  local selected = nil

  M.picker(options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick, apply_numeration)

  if not selected then coroutine.yield() end

  return selected
end

return M
