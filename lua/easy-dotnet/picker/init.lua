local M = {}

---@return "telescope"|"fzf"|"snacks"|"basic" active_picker
local function get_active_picker()
  ---@type PickerType
  local selected_picker = require("easy-dotnet.options").get_option("picker")

  if selected_picker ~= nil and selected_picker ~= "telescope" and selected_picker ~= "fzf" and selected_picker ~= "snacks" and selected_picker ~= "basic" then
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
    elseif selected_picker == "snacks" and pcall(require, "snacks") then
      return "snacks"
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
  elseif pcall(require, "snacks") then
    return "snacks"
  else
    return "basic"
  end
end

M.search_nuget = function()
  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").nuget_search()
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").nuget_search()
  elseif active_picker == "snacks" then
    return require("easy-dotnet.picker._snacks").nuget_search()
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
  elseif active_picker == "snacks" then
    return require("easy-dotnet.picker._snacks").migration_picker(opts, migration)
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
  elseif active_picker == "snacks" then
    return require("easy-dotnet.picker._snacks").preview_picker(options, on_select_cb, title, get_secret_path, readFile)
  else
    return require("easy-dotnet.picker._base").preview_picker(bufnr, options, on_select_cb, title, previewer)
  end
end

M.picker = function(bufnr, options, on_select_cb, title, autopick, apply_numeration)
  if autopick == nil then autopick = true end
  if apply_numeration == nil then apply_numeration = true end

  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").picker(bufnr, options, on_select_cb, title, autopick, apply_numeration)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").picker(bufnr, options, on_select_cb, title, autopick, apply_numeration)
  elseif active_picker == "snacks" then
    return require("easy-dotnet.picker._snacks").picker(options, on_select_cb, title, autopick, apply_numeration)
  else
    return require("easy-dotnet.picker._base").picker(bufnr, options, on_select_cb, title, autopick, apply_numeration)
  end
end

M.pick_sync = function(bufnr, options, title, autopick, apply_numeration)
  if autopick == nil then autopick = true end
  if apply_numeration == nil then apply_numeration = true end

  local active_picker = get_active_picker()

  if active_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").pick_sync(bufnr, options, title, autopick, apply_numeration)
  elseif active_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").pick_sync(bufnr, options, title, autopick, apply_numeration)
  elseif active_picker == "snacks" then
    return require("easy-dotnet.picker._snacks").pick_sync(options, title, autopick, apply_numeration)
  else
    return require("easy-dotnet.picker._base").pick_sync(bufnr, options, title, autopick, apply_numeration)
  end
end

return M
