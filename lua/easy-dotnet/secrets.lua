local M = {}
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local csproj_parse = parsers.csproj_parser
local sln_parse = parsers.sln_parser
local picker = require("easy-dotnet.picker")
local error_messages = require("easy-dotnet.error-messages")
local polyfills = require("easy-dotnet.polyfills")

--- Reads a file and returns the lines in a lua table
---@param filePath string
---@return table | nil
local function readFile(filePath)
  local file = io.open(filePath, "r")
  if not file then return nil end

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
  if not entry.value.secrets then
    vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Secrets file does not exist", "<CR> to create" })
    return
  end
  local content = readFile(get_secret_path(entry.value.secrets))
  if content ~= nil then vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, content) end
end

local function create_directory(dir)
  if vim.loop.fs_stat(dir) == nil then -- Check if directory exists
    assert(vim.loop.fs_mkdir(dir, 493), "Failed to create directory: " .. dir) -- 493 = 0755 permissions
  end
end

local function append_to_file(file, content) vim.fn.writefile(content, file) end
--- Initializes secrets for a given project
---@param project_file_path string
---@param get_secret_path function
---@return string
local init_secrets = function(project_file_path, get_secret_path)
  local function extract_secret_guid(commandOutput)
    local guid = commandOutput:match("UserSecretsId to '([%a%d%-]+)'")
    return guid
  end

  if not project_file_path then error("Error no project path when creating user secrets") end

  local res = vim.fn.system({
    "dotnet",
    "user-secrets",
    "init",
    "--project",
    vim.fn.shellescape(project_file_path),
  })
  if vim.v.shell_error ~= 0 then error("Failed to create user-secrets for " .. project_file_path) end
  local guid = extract_secret_guid(res)
  if not guid then error("User secrets created but unable to extract secrets guid") end
  local path = get_secret_path(guid)
  local parentDir = vim.fs.dirname(path)
  create_directory(parentDir)
  append_to_file(path, { "{ }" })

  logger.info("User secrets created")
  return guid
end

local function csproj_fallback(get_secret_path)
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local csproj = csproj_parse.get_project_from_project_file(csproj_path)
  if not csproj.secrets then
    local secret_id = init_secrets(csproj.path, get_secret_path)
    csproj.secrets = secret_id
  end
  picker.picker(nil, { csproj }, function(i)
    local path = get_secret_path(i.secrets)
    local parentDir = vim.fs.dirname(path)
    create_directory(parentDir)
    vim.cmd("edit! " .. path)
  end, "Secrets")
end

M.edit_secrets_picker = function(get_secret_path)
  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    csproj_fallback(get_secret_path)
    return
  end

  local projectsWithSecrets = polyfills.tbl_filter(function(i) return i.path ~= nil and i.runnable == true end, sln_parse.get_projects_from_sln(solutionFilePath))

  if #projectsWithSecrets == 0 then
    logger.error(error_messages.no_runnable_projects_found)
    return
  end
  picker.preview_picker(nil, projectsWithSecrets, function(item)
    if not item.secrets then
      local secret_id = init_secrets(item.path, get_secret_path)
      item.secrets = secret_id
    end
    local path = get_secret_path(item.secrets)
    local parentDir = vim.fs.dirname(path)
    create_directory(parentDir)
    vim.cmd("edit! " .. path)
  end, "Secrets", function(self, entry) secrets_preview(self, entry, get_secret_path) end, get_secret_path, readFile)
end

return M
