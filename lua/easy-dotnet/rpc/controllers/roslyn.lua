---@class easy-dotnet.RPC.Client.Roslyn
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field roslyn_bootstrap_file fun(self: easy-dotnet.RPC.Client.Roslyn, file_path: string, type: "Class" | "Interface" | "Record", prefer_file_scoped: boolean, cb?: fun(success: true), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field roslyn_bootstrap_file_json fun(self: easy-dotnet.RPC.Client.Roslyn, file_path: string, json_data: string, prefer_file_scoped: boolean, cb?: fun(success: true), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field roslyn_scope_variables fun(self: easy-dotnet.RPC.Client.Roslyn, file_path: string, line: number, cb?: fun(variables: easy-dotnet.Roslyn.VariableLocation[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field get_workspace_diagnostics fun(self: easy-dotnet.RPC.Client.Roslyn, project_path: string, include_warnings: boolean, cb?: fun(res: easy-dotnet.RPC.Response), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

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

return M
