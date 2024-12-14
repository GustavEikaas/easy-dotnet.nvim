local M = {}
local extensions = require("easy-dotnet.extensions")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local picker = require("easy-dotnet.picker")
local error_messages = require("easy-dotnet.error-messages")

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
---@param get_secret_path function
local secrets_preview = function(self, entry, get_secret_path)
  print(vim.inspect(entry))
  if not entry.value.secrets then
    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Secrets file does not exist", "<CR> to create" })
    return
  end
  local content = readFile(get_secret_path(entry.value.secrets))
  if content ~= nil then
    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content)
  end
end

local function create_directory(dir)
  if vim.loop.fs_stat(dir) == nil then                                         -- Check if directory exists
    assert(vim.loop.fs_mkdir(dir, 493), "Failed to create directory: " .. dir) -- 493 = 0755 permissions
  end
end

local function append_to_file(file, content)
  local fd = assert(vim.loop.fs_open(file, "a+", 420)) -- 420 = 0644 permissions
  assert(vim.loop.fs_write(fd, content, -1))           -- Append content
  vim.loop.fs_close(fd)
end
--- Initializes secrets for a given project
---@param project_file_path string
---@param get_secret_path function
---@return string
local init_secrets = function(project_file_path, get_secret_path)
  local function extract_secret_guid(commandOutput)
    local guid = commandOutput:match("UserSecretsId to '([%a%d%-]+)'")
    return guid
  end

  local handler = io.popen("Dotnet user-secrets init --project " .. project_file_path)
  if handler == nil then
    error("Failed to create user-secrets for " .. project_file_path)
  end
  local value = handler:read("*a")
  local guid = extract_secret_guid(value)
  local path = get_secret_path(guid)
  local parentDir = vim.fs.dirname(path)
  create_directory(parentDir)
  append_to_file(path, "{ }\n")

  handler:close()
  vim.notify("User secrets created")
  return guid
end

local function csproj_fallback(get_secret_path)
  local csproj_path = csproj_parse.find_project_file()
  if (csproj_path == nil) then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local csproj = csproj_parse.get_project_from_csproj(csproj_path)
  if not csproj.secrets then
    local secret_id = init_secrets(csproj.path, get_secret_path)
    csproj.secrets = secret_id
  end
  picker.picker(nil, { csproj }, function(i)
    local path = get_secret_path(i.secrets)
    vim.cmd("edit! " .. path)
  end, "Secrets")
end

M.edit_secrets_picker = function(get_secret_path)
  local solutionFilePath = sln_parse.find_solution_file()
  print(solutionFilePath)
  if solutionFilePath == nil then
    csproj_fallback(get_secret_path)
    return
  end

  local projectsWithSecrets = extensions.filter(sln_parse.get_projects_from_sln(solutionFilePath), function(i)
    return i.path ~= nil and i.runnable == true
  end)

  if #projectsWithSecrets == 0 then
    vim.notify(error_messages.no_runnable_projects_found)
    return
  end

  picker.preview_picker(nil, projectsWithSecrets, function(item)
    print(vim.inspect(item))

    if not item.secrets then
      local secret_id = init_secrets(item.path, get_secret_path)
      item.secrets = secret_id
    end
    local path = get_secret_path(item.secrets)
    vim.cmd("edit! " .. path)
  end, "Secrets", function(self, entry)
    secrets_preview(self, entry, get_secret_path)
  end)
end

return M
