---@class RoslynClient
---@field _client StreamJsonRpc
---@field roslyn_bootstrap_file fun(self: RoslynClient, file_path: string, type: "Class" | "Interface" | "Record", prefer_file_scoped: boolean, cb?: fun(success: true), opts?: RPC_CallOpts): RPC_CallHandle
---@field roslyn_bootstrap_file_json fun(self: RoslynClient, file_path: string, json_data: string, prefer_file_scoped: boolean, cb?: fun(success: true), opts?: RPC_CallOpts): RPC_CallHandle
---@field roslyn_scope_variables fun(self: RoslynClient, file_path: string, line: number, cb?: fun(variables: VariableLocation[]), opts?: RPC_CallOpts): RPC_CallHandle
---@field get_workspace_diagnostics fun(self: RoslynClient, project_path: string, include_warnings: boolean, cb?: fun(res: RPC_Response), opts?: RPC_CallOpts): RPC_CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return RoslynClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:roslyn_bootstrap_file_json(file_path, json_data, prefer_file_scoped, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(res) cb(res.success) end,
    on_crash = opts.on_crash,
    method = "json-code-gen",
    params = { filePath = file_path, jsonData = json_data, preferFileScopedNamespace = prefer_file_scoped },
  })()
end

function M:roslyn_bootstrap_file(file_path, type, prefer_file_scoped, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(res) cb(res.success) end,
    on_crash = opts.on_crash,
    method = "roslyn/bootstrap-file",
    params = { filePath = file_path, kind = type, preferFileScopedNamespace = prefer_file_scoped },
  })()
end

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

return M
