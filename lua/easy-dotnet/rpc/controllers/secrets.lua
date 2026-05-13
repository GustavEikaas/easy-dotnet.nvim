local dotnet_client = require("easy-dotnet.rpc.dotnet-client")

---@class easy-dotnet.RPC.Client.Secrets
local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Secrets
function M.new(client)
  local instance = setmetatable({}, M)
  instance._client = client
  return instance
end

---@param opts? easy-dotnet.RPC.CallOpts
---@return easy-dotnet.RPC.CallHandle
function M:open(opts)
  opts = opts or {}
  return dotnet_client.create_rpc_call({
    client = self._client,
    method = "user-secrets/open",
    params = {},
    on_crash = opts.on_crash,
  })()
end

return M
