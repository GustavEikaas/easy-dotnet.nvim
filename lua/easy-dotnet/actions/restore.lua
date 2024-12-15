local M = {}
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

---@param term function
M.restore = function(term)
  term = term or require("easy-dotnet.options").options.terminal
  local project = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if project == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  term(project, "restore", "")
end


return M
