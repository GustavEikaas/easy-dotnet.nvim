local M = {}

local window = require("easy-dotnet.project-view.render")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local csproj_parser = require("easy-dotnet.parsers.csproj-parse")
local error_messages = require("easy-dotnet.error-messages")
local picker = require("easy-dotnet.picker")
local default_manager = require("easy-dotnet.default-manager")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")

local function select_project(solution_file_path, cb)
  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    logger.error(error_messages.no_projects_found)
    return
  end

  local proj = picker.picker(nil, projects, function(i)
    cb(i)
    default_manager.set_default_project(i, solution_file_path, "view")
  end, "Select a project")
  return proj
end

M.open_or_toggle = function()
  current_solution.get_or_pick_solution(function(sln_path)
    if not sln_path then
      local project_file = csproj_parser.find_project_file()
      if not project_file then
        logger.error(error_messages.no_project_definition_found)
        return
      end
      local project = csproj_parser.get_project_from_project_file(project_file)
      window.render(project, nil)
      return
    end
    select_project(sln_path, function(i) window.render(i, sln_path) end)
  end)
end

M.open_or_toggle_default = function()
  if window.project then
    window.toggle()
    return
  end

  current_solution.get_or_pick_solution(function(sln_path)
    if not sln_path then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local default = default_manager.check_default_project(sln_path, "view")
    if default ~= nil then
      window.render(default, sln_path)
      return
    end

    select_project(sln_path, function(i) window.render(i, sln_path) end)
  end)
end

return M
