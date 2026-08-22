local state = require("easy-dotnet.project-view.state")
local render = require("easy-dotnet.project-view.render")
local logger = require("easy-dotnet.logger")

local M = {}

local function has_action(actions, name)
  if not actions then return false end
  for _, a in ipairs(actions) do
    if a == name then return true end
  end
  return false
end

local function open_browser(url)
  local opener = vim.fn.has("mac") == 1 and "open" or vim.fn.has("win32") == 1 and "start" or "xdg-open"
  vim.fn.jobstart({ opener, url }, { detach = true })
end

local function run(invoke)
  if not state.project_path then return end
  invoke(state.project_path)
end

---@param buf integer
---@param client easy-dotnet.RPC.Client.Dotnet
---@param options table
function M.register(buf, client, options)
  local function map(lhs, desc, fn) vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, noremap = true, silent = true }) end

  map("a", "Add", function()
    local row = render.row_at_cursor()
    local section = row and row.section
    if section == "projectrefs" then
      run(function(path) client.project_view:add_project_reference(path) end)
    else
      run(function(path) client.project_view:add_package(path) end)
    end
  end)

  map("x", "Remove", function()
    local row = render.row_at_cursor()
    if not row then return end
    if row.kind == "package" and has_action(row.pkg.availableActions, "RemovePackage") then
      local id = row.pkg.id
      run(function(path) client.project_view:remove_package(path, id) end)
    elseif row.kind == "projectref" and has_action(row.ref.availableActions, "RemoveProjectReference") then
      local target = row.ref.path
      run(function(path) client.project_view:remove_project_reference(path, target) end)
    else
      logger.warn("Nothing to remove here")
    end
  end)

  map("u", "Update package", function()
    local row = render.row_at_cursor()
    if not row or row.kind ~= "package" then
      logger.warn("Move the cursor onto a package to update it")
      return
    end
    if not has_action(row.pkg.availableActions, "UpdatePackage") then
      logger.warn("Update not available for this package")
      return
    end
    local id = row.pkg.id
    if row.pkg.isOutdated and row.pkg.latestVersion then
      local latest = row.pkg.latestVersion
      run(function(path) client.project_view:upgrade_package(path, id, latest) end)
    else
      run(function(path) client.project_view:update_package(path, id) end)
    end
  end)

  map("b", "Browse package", function()
    local row = render.row_at_cursor()
    if not row or row.kind ~= "package" then
      logger.warn("Move the cursor onto a package to browse it")
      return
    end
    open_browser("https://www.nuget.org/packages/" .. row.pkg.id)
  end)

  map("o", "Check outdated", function()
    run(function(path) client.project_view:check_outdated(path) end)
  end)

  map("U", "Upgrade all", function()
    run(function(path) client.project_view:upgrade_all_outdated(path) end)
  end)

  map("r", "Refresh", function()
    run(function(path) client.project_view:refresh(path) end)
  end)

  map("gf", "Open project file", function()
    if not state.project_path then return end
    render.hide()
    vim.cmd("edit " .. vim.fn.fnameescape(state.project_path))
  end)

  local function close()
    render.hide()
    state.clear()
  end
  map("q", "Close", close)
  map("<Esc>", "Close", close)
end

return M
