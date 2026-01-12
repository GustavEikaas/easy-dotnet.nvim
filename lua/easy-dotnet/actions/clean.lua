local M = {}
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local csproj_parse = parsers.csproj_parser
local error_messages = require("easy-dotnet.error-messages")

M.clean_solution = function(args)
  args = args or ""

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()

    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    local command = string.format("dotnet clean %s %s", solution_path, args)
    local err_lines = {}

    vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stderr = function(_, data)
        for _, line in ipairs(data) do
          if #line > 0 then table.insert(err_lines, line) end
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          logger.error("Command failed " .. command)
        else
          logger.info(solution_path .. " cleaned")
        end
      end,
    })
  end)
end

return M
