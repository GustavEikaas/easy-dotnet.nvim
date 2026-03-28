---@class easy-dotnet.RPC.Client.Test
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field set_run_settings fun(self: easy-dotnet.RPC.Client.Test)

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Test
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:set_run_settings() self._client.notify("test/set-project-run-settings", {}) end

return M
