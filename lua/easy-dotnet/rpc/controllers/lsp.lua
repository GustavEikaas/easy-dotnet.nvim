---@class LspClient
---@field _client StreamJsonRpc
---@field lsp_start fun(self: LspClient, cb?: fun(res: LspStartResponse), opts?: RPC_CallOpts): RPC_CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return LspClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class LspStartResponse
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
