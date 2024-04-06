local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser

local function csproj_fallback(term)
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify("No .sln file or .csproj file found")
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } }, function(i)
    term(i.path, "build")
  end, "Build project(s)")
end

---@param term function
M.build_project_picker = function(term)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(term)
    return
  end
  local projects = sln_parse.get_projects_from_sln(solutionFilePath)

  if #projects == 0 then
    vim.notify("No runnable projects found")
    return
  end

  -- Add an entry for the solution file
  table.insert(projects, {
    path = solutionFilePath,
    display = "All"
  })

  picker.picker(nil, projects, function(i)
    term(i.path, "build")
  end, "Build project(s)")
end

return M
