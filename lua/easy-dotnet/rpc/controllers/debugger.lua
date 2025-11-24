---@class DebuggerClient
---@field _client StreamJsonRpc
---@field debugger_start fun(self: DebuggerClient, request: DebuggerStartRequest, cb?: fun(res: DebuggerStartResponse), opts?: RPC_CallOpts): RPC_CallHandle
---@field aspire_debug fun(self: DebuggerClient, project_path: string, cb?: fun(res: DebuggerStartResponse), opts?: RPC_CallOpts): RPC_CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return DebuggerClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class DebuggerStartRequest
---@field targetPath string
---@field targetFramework string?
---@field configuration string?
---@field launchProfileName string?

---@class DebuggerStartResponse
---@field success boolean
---@field port integer | nil

function M:debugger_start(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "debugger/start",
    params = { request = request },
  })()
end

function M:aspire_debug(project_path, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "aspire/startDebugSession",
    params = { projectPath = project_path },
  })()
end

return M
