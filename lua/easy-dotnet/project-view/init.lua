local M = {}

local window = require("easy-dotnet.project-view.render")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local picker = require("easy-dotnet.picker")
local default_manager = require("easy-dotnet.default-manager")

local function select_project(solution_file_path, cb)
  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end

  local proj = picker.picker(nil, projects, function(i)
    cb(i)
    default_manager.set_default_project(i, solution_file_path, "view")
  end, "Select a project")
  return proj
end

M.open_or_toggle = function()
  local sln_path = sln_parse.find_solution_file()
  select_project(sln_path, function(i)
    window.render(i, sln_path)
  end)
end

M.open_or_toggle_default = function()
  if window.project then
    window.toggle()
    return
  end
  local sln_path = sln_parse.find_solution_file()
  if not sln_path then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local default = default_manager.check_default_project(sln_path, "view")
  if default ~= nil then
    window.render(default, sln_path)
    return
  end

  select_project(sln_path, function(i)
    window.render(i, sln_path)
  end)
end

return M
