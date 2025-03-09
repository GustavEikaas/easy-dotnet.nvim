local M = {}

---@return "telescope"|"fzf"|"basic" active_picker
local function get_active_picker()
  ---@type PickerType
  local selected_picker = require("easy-dotnet.options").get_option("picker")

  if selected_picker ~= nil and selected_picker ~= "telescope" and selected_picker ~= "fzf" and selected_picker ~= "basic" then
    vim.notify(string.format("Invalid picker type: '%s'. Using auto-detection instead.", selected_picker), vim.log.levels.WARN)
    selected_picker = nil
  end

  -- if picker is specified, check if it's available
  if selected_picker ~= nil then
    -- check each known picker in order
    if selected_picker == "telescope" and pcall(require, "telescope") then
      return "telescope"
    elseif selected_picker == "fzf" and pcall(require, "fzf-lua") then
      return "fzf"
    elseif selected_picker == "basic" then
      return "basic"
    end
  end

  -- if picker is not specified or specified picker is not available,
  -- automatically detect available picker
  if pcall(require, "telescope") then
    return "telescope"
  elseif pcall(require, "fzf-lua") then
    return "fzf"
  else
    return "basic"
  end
end

---@param cb function|nil
M.search_nuget = function(cb)
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").nuget_search(cb)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").nuget_search()
  else
    return require("easy-dotnet.picker._base").nuget_search()
  end
end

M.migration_picker = function(opts, migration)
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").migration_picker(opts, migration)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").migration_picker(opts, migration)
  else
    return require("easy-dotnet.picker._base").migration_picker(opts, migration)
  end
end

M.preview_picker = function(bufnr, options, on_select_cb, title, previewer, get_secret_path, readFile)
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").preview_picker(bufnr, options, on_select_cb, title, get_secret_path, readFile)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").preview_picker(bufnr, options, on_select_cb, title, previewer)
  else
    return require("easy-dotnet.picker._base").preview_picker(bufnr, options, on_select_cb, title, previewer)
  end
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").picker(bufnr, options, on_select_cb, title, autopick)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").picker(bufnr, options, on_select_cb, title, autopick)
  else
    return require("easy-dotnet.picker._base").picker(bufnr, options, on_select_cb, title, autopick)
  end
end

M.pick_sync = function(bufnr, options, title, autopick)
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").pick_sync(bufnr, options, title, autopick)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").pick_sync(bufnr, options, title, autopick)
  else
    return require("easy-dotnet.picker._base").pick_sync(bufnr, options, title, autopick)
  end
end

return M
