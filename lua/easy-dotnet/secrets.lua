local M = {}
local extensions = require("easy-dotnet.extensions")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local picker = require("easy-dotnet.picker")

--- Reads a file and returns the lines in a lua table
---@param filePath string
---@return table | nil
local function readFile(filePath)
  local file = io.open(filePath, "r")
  if not file then
    return nil
  end

  local content = {}
  for line in file:lines() do
    table.insert(content, line)
  end

  file:close()
  return content
end

--- Generates a secret preview for telescope
---@param self table Telescope self
---@param entry table
local secrets_preview = function(self, entry)
  if entry.value.secrets == false then
    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Secrets file does not exist", "<CR> to create" })
    return
  end
  local home_dir = vim.fn.expand('~')
  local secret_path = home_dir ..
      '\\AppData\\Roaming\\Microsoft\\UserSecrets\\' .. entry.value.secrets .. "\\secrets.json"
  local content = readFile(secret_path)
  vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
end

--- Initializes secrets for a given project
---@param project_file_path string
---@return string
local init_secrets = function(project_file_path)
  local function extract_secret_guid(commandOutput)
    local guid = commandOutput:match("UserSecretsId to '([%a%d%-]+)'")
    return guid
  end

  local handler = io.popen("Dotnet user-secrets init --project " .. project_file_path)
  if handler == nil then
    error("Failed to create user-secrets for " .. project_file_path)
  end
  local value = handler:read("*a")
  require("easy-dotnet.debug").write_to_log(value)
  local guid = extract_secret_guid(value)

  require("easy-dotnet.debug").write_to_log("secret_guid " .. guid)
  handler:close()
  vim.notify("User secrets created")
  return guid
end

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
    return i.path ~= nil and i.runnable == true
  end)

  if #projectsWithSecrets == 0 then
    vim.notify(" No secrets found")
    return
  end
  picker.preview_picker(nil, projectsWithSecrets, function(item)
    if item.secrets == false then
      local secret_id = init_secrets(item.path)
      item.secrets = secret_id
    end
    on_secret_selected(item)
  end, "Secrets", secrets_preview)
end

return M
