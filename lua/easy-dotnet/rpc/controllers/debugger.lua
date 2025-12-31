---@class easy-dotnet.RPC.Client.Debugger
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field debugger_start fun(self: easy-dotnet.RPC.Client.Debugger, request: easy-dotnet.Debugger.StartRequest, cb?: fun(res: easy-dotnet.Debugger.StartResponse), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Debugger
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.Debugger.StartRequest
---@field targetPath string
---@field targetFramework string?
---@field configuration string?
---@field launchProfileName string?

---@class easy-dotnet.Debugger.StartResponse
---@field success boolean
---@field port integer | nil

function M:debugger_start(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = { name = "Starting debugger", on_success_text = "Debugger attached", on_error_text = "Failed to start debugger" },
    cb = cb,
    on_crash = opts.on_crash,
    method = "debugger/start",
    params = { request = request },
  })()
end

return M
