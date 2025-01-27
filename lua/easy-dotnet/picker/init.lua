local M = {}
local function has_telescope()
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  return selected_picker == "telescope" and pcall(require, "telescope")
end
local function has_fzf()
  local selected_picker = require("easy-dotnet.options").get_option("picker")
  return selected_picker == "fzf" and pcall(require, "fzf-lua")
end

---@param cb function|nil
M.search_nuget = function(cb)
  if has_fzf then
    return require("easy-dotnet.picker._fzf").nuget_search(cb)
  elseif has_telescope then
    return require("easy-dotnet.picker._telescope").nuget_search()
  else
    return require("easy-dotnet.picker._base").nuget_search()
  end
end

M.migration_picker = function(opts, migration)
  if has_fzf then
    return require("easy-dotnet.picker._fzf").migration_picker(opts, migration)
  elseif has_telescope then
  else
    return require("easy-dotnet.picker._base").migration_picker(opts, migration)
  end
end

M.preview_picker = function(bufnr, options, on_select_cb, title, previewer, get_secret_path, readFile)
  if has_fzf then
    return require("easy-dotnet.picker._fzf").preview_picker(bufnr, options, on_select_cb, title, get_secret_path, readFile)
  elseif has_telescope then
    return require("easy-dotnet.picker._telescope").preview_picker(bufnr, options, on_select_cb, title, previewer)
  else
    return require("easy-dotnet.picker._base").preview_picker(bufnr, options, on_select_cb, title, previewer)
  end
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if has_fzf then
    return require("easy-dotnet.picker._fzf").picker(bufnr, options, on_select_cb, title, autopick)
  elseif has_telescope then
    return require("easy-dotnet.picker._telescope").picker(bufnr, options, on_select_cb, title, autopick)
  else
    return require("easy-dotnet.picker._base").picker(bufnr, options, on_select_cb, title, autopick)
  end
end

M.pick_sync = function(bufnr, options, title, autopick)
  if has_fzf then
    return require("easy-dotnet.picker._fzf").pick_sync(bufnr, options, title, autopick)
  elseif has_telescope then
    return require("easy-dotnet.picker._telescope").pick_sync(bufnr, options, title, autopick)
  else
    return require("easy-dotnet.picker._base").pick_sync(bufnr, options, title, autopick)
  end
end

return M
