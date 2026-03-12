---@class easy-dotnet.RPC.Client.Workspace
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field workspace_build fun(self: easy-dotnet.RPC.Client.Workspace, use_default: boolean, use_terminal: boolean, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Workspace
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:workspace_build(use_default, use_terminal, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = nil,
    on_crash = opts.on_crash,
    method = "workspace/build",
    params = {
      useDefault = use_default,
      useTerminal = use_terminal,
    },
  })()
end

return M
