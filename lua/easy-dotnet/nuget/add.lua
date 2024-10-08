local picker = require("easy-dotnet.picker")
local csproj = require("easy-dotnet.parsers.csproj-parse")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")

local M = {}

--dotnet package search EntityFrameworkCore.Sql --format json --take 2
function M.add_package()
  local sln = require("easy-dotnet.parsers.sln-parse").find_solution_file()
  assert(sln, "No solution file found")
  local projects = sln_parse.get_projects_from_sln(sln)

  local project = picker.pick_sync(nil, projects, "Pick project")

  local input = { "echo", "hello" }
  local opts = {
    finder = require("telescope.finders").new_async_job(input)

  }
  local picker = require("telescope.pickers").new(opts):find()
  -- dynamic_picker()
end

return M
