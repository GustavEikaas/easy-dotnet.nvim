local M = {}
local extensions = require("easy-dotnet.extensions")
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

---@param term function
local function csproj_fallback(term)
  local csproj_path = csproj_parse.find_project_file()
  if (csproj_path == nil) then
    vim.notify(error_messages.no_project_definition_found)
    return
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } },
    function(i) term(i.path, "run") end, "Run project")
end

---@param term function
---@param use_default boolean
---@param args string | nil
M.run_project_picker = function(term, use_default, args)
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback(term)
    return
  end

  local default = default_manager.check_default_project(solution_file_path, "run")
  if default ~= nil and use_default == true then
    term(default.path, "run", args)
    return
  end

  local projects = extensions.filter(sln_parse.get_projects_from_sln(solution_file_path), function(i)
    return i.runnable == true
  end)

  if #projects == 0 then
    vim.notify(error_messages.no_runnable_projects_found)
    return
  end
  picker.picker(nil, projects, function(i)
    term(i.path, "run", args)
    default_manager.set_default_project(i, solution_file_path, "run")
  end, "Run project")
end

return M
