local M = {}

---@param cb function|nil
M.search_nuget = function(cb)
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").nuget_search(cb)
  elseif selected_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").nuget_search()
  else
    return require("easy-dotnet.picker._base").nuget_search()
  end
end

M.migration_picker = function(opts, migration)
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").migration_picker(opts, migration)
  elseif selected_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").migration_picker(opts, migration)
  else
    return require("easy-dotnet.picker._base").migration_picker(opts, migration)
  end
end

M.preview_picker = function(bufnr, options, on_select_cb, title, previewer, get_secret_path, readFile) --, readFile)
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").preview_picker(bufnr, options, on_select_cb, title, get_secret_path, readFile) --, readFile)
  elseif selected_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").preview_picker(bufnr, options, on_select_cb, title, previewer)
  else
    return require("easy-dotnet.picker._base").preview_picker(bufnr, options, on_select_cb, title, previewer)
  end
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").picker(bufnr, options, on_select_cb, title, autopick)
  elseif selected_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").picker(bufnr, options, on_select_cb, title, autopick)
  else
    return require("easy-dotnet.picker._base").picker(bufnr, options, on_select_cb, title, autopick)
  end
end

M.pick_sync = function(bufnr, options, title, autopick)
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  if selected_picker == "fzf" then
    return require("easy-dotnet.picker._fzf").pick_sync(bufnr, options, title, autopick)
  elseif selected_picker == "telescope" then
    return require("easy-dotnet.picker._telescope").pick_sync(bufnr, options, title, autopick)
  else
    return require("easy-dotnet.picker._base").pick_sync(bufnr, options, title, autopick)
  end
end

return M
