local M = {}
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

---@param term function
M.restore = function(term, args)
  args = args or ""
  term = term or require("easy-dotnet.options").options.terminal
  local project = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if project == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local cmd = require("easy-dotnet.options").options.server.use_visual_studio == true and string.format("nuget restore %s %s", project, args) or string.format("dotnet restore %s %s", project, args)
  term(project, "restore", args, { cmd = cmd })
end

return M
