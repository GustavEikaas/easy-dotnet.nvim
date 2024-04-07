local M = {}
local extensions = require("easy-dotnet.extensions")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local picker = require("easy-dotnet.picker")

local function csproj_fallback(on_secret_selected)
  local csproj_path = csproj_parse.find_csproj_file()
  if (csproj_path == nil) then
    vim.notify("No .sln or .csproj file found in cwd")
    return
  end
  local csproj = csproj_parse.get_project_from_csproj(csproj_path)
  if csproj.secrets == false then
    vim.notify(csproj_path .. " has no secret file")
    return
  end
  picker.picker(nil, { csproj }, on_secret_selected, "Secrets")
end


M.edit_secrets_picker = function(on_secret_selected)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(on_secret_selected)
    return
  end

  local projectsWithSecrets = extensions.filter(sln_parse.get_projects_from_sln(solutionFilePath), function(i)
    return i.secrets ~= false and i.path ~= nil and i.runnable == true
  end)

  if #projectsWithSecrets == 0 then
    vim.notify(" No secrets found")
    return
  end
  picker.picker(nil, projectsWithSecrets, on_secret_selected, "Secrets")
end

return M
