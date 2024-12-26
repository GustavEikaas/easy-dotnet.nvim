local M = {}
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local error_messages = require("easy-dotnet.error-messages")

M.clean_solution = function(args)
  args = args or ""
  local solutionFilePath = sln_parse.find_solution_file() or csproj_parse.find_project_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local command = string.format("dotnet clean %s %s", solutionFilePath, args)
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
        vim.notify("Command failed " .. command)
      else
        vim.notify(solutionFilePath .. " cleaned")
      end
    end,
  })
end

return M
