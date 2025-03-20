local M = {}
local picker = require("easy-dotnet.picker")
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")
local polyfills = require("easy-dotnet.polyfills")

---@param term function
local function csproj_fallback(term, args)
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end
  picker.picker(nil, { { name = csproj_path, display = csproj_path, path = csproj_path } }, function(i) term(i.path, "watch", args) end, "Run project")
end

---@param term function | nil
---@param use_default boolean | nil
---@param args string | nil
M.run_project_picker = function(term, use_default, args)
  term = term or require("easy-dotnet.options").options.terminal
  use_default = use_default or false
  args = args or ""
  local default_manager = require("easy-dotnet.default-manager")
  local solution_file_path = sln_parse.find_solution_file()
  if solution_file_path == nil then
    csproj_fallback(term, args)
    return
  end

  local default = default_manager.check_default_project(solution_file_path, "watch")
  if default ~= nil and use_default == true then
    term(default.path, "watch", args)
    return
  end

  local projects = polyfills.tbl_filter(function(i) return i.runnable == true end, sln_parse.get_projects_from_sln(solution_file_path))

  if #projects == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  picker.picker(nil, projects, function(i)
    term(i.path, "watch", args)
    default_manager.set_default_project(i, solution_file_path, "watch")
  end, "Run project")
end

return M
