local picker = require("easy-dotnet.pickers")
local sln_parse = require("easy-dotnet.parsers.sln-parse")

local M = {}

M.pick_projects = function()
  local sln = require("easy-dotnet.parsers.sln-parse").find_solution_file()
  assert(sln, "No solution file found")
  local projects = sln_parse.get_projects_from_sln(sln)

  local project = picker.pick_sync(nil, projects, "Pick project")
  local sorted = {
    project,
  }
  for _, value in ipairs(projects) do
    if value ~= project then table.insert(sorted, value) end
  end
  local startup_project = picker.pick_sync(nil, sorted, "Pick startup project")
  assert(project, "No project selected")
  assert(startup_project, "No startup project selected")
  return {
    project = project,
    startup_project = startup_project,
  }
end

return M
