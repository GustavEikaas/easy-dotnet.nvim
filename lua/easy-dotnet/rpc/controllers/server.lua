---@class easy-dotnet.RPC.Client.Server
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field server_set_log_level fun(self: easy-dotnet.RPC.Client.Server, level: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field server_log_dump fun(self: easy-dotnet.RPC.Client.Server, cb?: fun(res: string[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field server_log_dump_build_server fun(self: easy-dotnet.RPC.Client.Server, cb?: fun(res: string[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Server
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:server_set_log_level(level, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "_server/setLogLevel",
    params = { level = level },
  })()
end

function M:server_log_dump(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "_server/logdump",
    params = {},
  })()
end

function M:server_log_dump_build_server(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "_server/logdump/buildserver",
    params = {},
  })()
end

return M
