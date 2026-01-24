local M = {}
local parsers = require("easy-dotnet.parsers")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
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

--- Initializes secrets for a given project
---@param project easy-dotnet.Project.Project
local init_secrets = function(project)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client:secrets_init(project.path, function(res) vim.cmd("edit! " .. res.filePath) end)
  end)
end

local function csproj_fallback(get_secret_path)
  local csproj_path = csproj_parse.find_project_file()
  if csproj_path == nil then
    logger.error(error_messages.no_project_definition_found)
    return
  end

  local csproj = csproj_parse.get_project_from_project_file(csproj_path)
  if not csproj.secrets then return init_secrets(csproj) end
  picker.picker(nil, { csproj }, function(i)
    local path = get_secret_path(i.secrets)
    local parentDir = vim.fs.dirname(path)
    create_directory(parentDir)
    vim.cmd("edit! " .. path)
  end, "Secrets")
end

M.edit_secrets_picker = function(get_secret_path)
  current_solution.get_or_pick_solution(function(solution_path)
    if solution_path == nil then
      csproj_fallback(get_secret_path)
      return
    end

    local projectsWithSecrets = polyfills.tbl_filter(function(i) return i.path ~= nil and i.runnable == true end, sln_parse.get_projects_from_sln(solution_path))

    if #projectsWithSecrets == 0 then
      logger.error(error_messages.no_runnable_projects_found)
      return
    end
    picker.preview_picker(nil, projectsWithSecrets, function(item)
      if not item.secrets then return init_secrets(item) end
      local path = get_secret_path(item.secrets)
      local parentDir = vim.fs.dirname(path)
      create_directory(parentDir)
      vim.cmd("edit! " .. path)
    end, "Secrets", function(self, entry) secrets_preview(self, entry, get_secret_path) end, get_secret_path, readFile)
  end)
end

return M
