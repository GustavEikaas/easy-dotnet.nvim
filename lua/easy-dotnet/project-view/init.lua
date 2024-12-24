local M = {}

local window = require("easy-dotnet.project-view.render")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local picker = require("easy-dotnet.picker")

local function select_project(solution_file_path, cb)
  local projects = sln_parse.get_projects_from_sln(solution_file_path)

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end

  local proj = picker.picker(nil, projects, function(i)
    cb(i)
  end, "Build project(s)")
  return proj
end


M.open = function()
  local sln_path = sln_parse.find_solution_file()
  select_project(sln_path, function(i)
    window.render(i, sln_path)
  end)
end

vim.api.nvim_create_user_command("NS", function()
  M.open()
end, {})

return M
