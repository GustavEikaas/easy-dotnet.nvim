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
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "lsp/start",
    params = vim.empty_dict(),
  })()
end

return M
