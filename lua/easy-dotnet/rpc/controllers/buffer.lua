---@class easy-dotnet.RPC.Client.Buffer
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field opened fun(self: easy-dotnet.RPC.Client.Buffer, path: string)
---@field closed fun(self: easy-dotnet.RPC.Client.Buffer, path: string)

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Buffer
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:opened(path)
  if not path or path == "" then return end
  self._client.notify("buffer/opened", { path = path })
end

function M:closed(path)
  if not path or path == "" then return end
  self._client.notify("buffer/closed", { path = path })
end

return M
