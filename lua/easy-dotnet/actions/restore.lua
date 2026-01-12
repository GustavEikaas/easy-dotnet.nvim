local M = {}
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local csproj_parse = parsers.csproj_parser
local error_messages = require("easy-dotnet.error-messages")

---@param term function
M.restore = function(term, args)
  args = args or ""
  term = term or require("easy-dotnet.options").options.terminal

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local cmd = require("easy-dotnet.options").options.server.use_visual_studio == true and string.format("nuget restore %s %s", solution_path, args)
      or string.format("dotnet restore %s %s", solution_path, args)
    term(solution_path, "restore", args, { cmd = cmd })
  end)
end

return M
