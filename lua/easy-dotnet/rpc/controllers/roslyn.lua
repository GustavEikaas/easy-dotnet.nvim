---@class easy-dotnet.RPC.Client.Roslyn
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field roslyn_scope_variables fun(self: easy-dotnet.RPC.Client.Roslyn, file_path: string, line: number, cb?: fun(variables: easy-dotnet.Roslyn.VariableLocation[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
-- luacheck: no max line length
---@field get_workspace_diagnostics fun(self: easy-dotnet.RPC.Client.Roslyn, project_path: string, include_warnings: boolean, cb?: fun(res: easy-dotnet.RPC.Response), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
-- luacheck: no max line length
---@field ef_generated_sql fun(self: easy-dotnet.RPC.Client.Roslyn, file_path: string, line: number, character: number, cb?: fun(res: easy-dotnet.Roslyn.EfGeneratedSql), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Roslyn
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.Roslyn.VariableLocation
---@field columnEnd integer
---@field columnStart integer
---@field identifier string
---@field lineEnd integer
---@field lineStart integer

function M:roslyn_scope_variables(file_path, line, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "roslyn/scope-variables",
    params = { sourceFilePath = file_path, lineNumber = line },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

function M:get_workspace_diagnostics(project_path, include_warnings, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = {
      name = "Getting workspace diagnostics...",
      on_error_text = "Failed to get diagnostics",
      on_success_text = "Diagnostics retrieved",
    },
    method = "roslyn/get-workspace-diagnostics",
    params = {
      targetPath = project_path,
      includeWarnings = include_warnings,
    },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

---@class easy-dotnet.Roslyn.EfGeneratedSql
---@field success boolean
---@field sql string|nil
---@field errorMessage string|nil
---@field targetProject string
---@field startupProject string
---@field startupProjectSource string
---@field warnings string[]

---@param file_path string
---@param line number 0-based cursor line
---@param character number 0-based cursor column
---@param cb? fun(res: easy-dotnet.Roslyn.EfGeneratedSql)
---@param opts? easy-dotnet.RPC.CallOpts
function M:ef_generated_sql(file_path, line, character, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = {
      name = "Generating SQL...",
      on_error_text = "Failed to generate SQL",
      on_success_text = "SQL generated",
    },
    method = "roslyn/ef-generated-sql",
    params = { sourceFilePath = file_path, line = line, character = character },
    cb = cb,
    on_crash = opts.on_crash,
  })()
end

return M
