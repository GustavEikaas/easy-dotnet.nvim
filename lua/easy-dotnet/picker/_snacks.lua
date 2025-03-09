local M = {}

M.nuget_search = function()
  local co = coroutine.running()
  local selected = nil

  require("snacks").picker.pick(nil, {
    title = "NuGet Search",
    live = true,
    layout = "select",
    format = "text",
    finder = function(_, ctx)
      local command = string.format('dotnet package search %s --format json | jq ".searchResult | .[] | .packages | .[] | .id"', ctx.filter.search)
      local command_result = vim.fn.system(command)

      local items = {}
      for single_package in command_result:gmatch("[^\n]+") do
          table.insert(items, { text = single_package:gsub('"', '') })
      end

      return items;
    end,
    confirm = function(picker, item)
      picker:close()
      selected = item.text
      if coroutine.status(co) ~= "running" then coroutine.resume(co) end
    end
  })

  if not selected then coroutine.yield() end

  return selected
end

M.migration_picker = function(opts, migrations)
  local picker_items = {}
  for _, migration in ipairs(migrations) do
    table.insert(picker_items, {
      text = migration,
      file = opts.entry_maker(migration).path
    })
  end

  require("snacks").picker.pick(nil, {
    items = picker_items,
    format = "text",
    preview = "file",
    title = "Migrations"
  })
end

local function get_preview_text(option, get_secret_path, read_file)
  if not option or not option.secrets then return  "Secrets file does not exist\n<CR> to create" end
  local content = read_file(get_secret_path(option.secrets))
  if content ~= nil then
    return table.concat(content, "\n")
  else
    return "Secrets file could not be read"
  end
end

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param get_secret_path function
---@param read_content function
M.preview_picker = function(bufnr, options, on_select_cb, title, get_secret_path, read_content)
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
        ft = "json"
      }
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
---@param bufnr number | nil
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param autopick boolean | nil
M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then autopick = true end
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local picker_items = {}
  for _, option in ipairs(options) do
    table.insert(picker_items, { text = option.display, option = option})
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

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param title string | nil
---@return T
M.pick_sync = function(bufnr, options, title, autopick)

  local co = coroutine.running()
  local selected = nil

  M.picker(bufnr, options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick)

  if not selected then coroutine.yield() end

  return selected
end

return M
