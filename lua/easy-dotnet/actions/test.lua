local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

local function csproj_fallback(on_select)
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify("No .sln file or .csproj file found")
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } },
    function(i) on_select(i.path, "test") end, "Run test")
end

M.run_test_picker = function(on_select)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(on_select)
    return
  end
  local projects = extensions.filter(sln_parse.get_projects_from_sln(solutionFilePath), function(i)
    return i.isTestProject == true
  end)

  if #projects == 0 then
    vim.notify(error_messages.no_test_projects_found)
    return
  end

  -- Add an entry for the solution file itself as it will run all tests in its definition
  table.insert(projects, {
    path = solutionFilePath,
    display = "All"
  })

  picker.picker(nil, projects, function(i) on_select(i.path, "test") end, "Run test")
end

M.test_solution = function(term)
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_csproj_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  term(solutionFilePath, "test")
end

return M
