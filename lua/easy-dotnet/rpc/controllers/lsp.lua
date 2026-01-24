---@class easy-dotnet.RPC.Client.Lsp
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field lsp_start fun(self: easy-dotnet.RPC.Client.Lsp, cb?: fun(res: easy-dotnet.Roslyn.LspStartResponse), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Lsp
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.Roslyn.LspStartResponse
---@field pipe string

function M:lsp_start(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local user_opts = require("easy-dotnet.options").get_option("lsp")

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "lsp/start",
    params = {
      useRoslynator = user_opts.roslynator_enabled or false,
      analyzerAssemblies = user_opts.analyzer_assemblies or {},
    },
  })()
end

return M
