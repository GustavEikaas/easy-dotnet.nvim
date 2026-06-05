---@class easy-dotnet.RPC.Client.NewFile
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field create_item fun(self: easy-dotnet.RPC.Client.NewFile, opts: easy-dotnet.RPC.Client.NewFile.CreateItemOpts): easy-dotnet.RPC.CallHandle
-- luacheck: no max line length
---@field bootstrap_file_v2 fun(self: easy-dotnet.RPC.Client.NewFile, file_path: string, type: "Class" | "Interface" | "Record", prefer_file_scoped: boolean, cb?: fun(success: true), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
-- luacheck: no max line length
---@field bootstrap_file_json_v2 fun(self: easy-dotnet.RPC.Client.NewFile, file_path: string, json_data: string, prefer_file_scoped: boolean, cb?: fun(success: true), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

---@class easy-dotnet.RPC.Client.NewFile.CreateItemOpts
---@field output_path string
---@field prefer_file_scoped_namespace boolean
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.NewFile
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:bootstrap_file_json_v2(file_path, json_data, prefer_file_scoped, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(res) cb(res.success) end,
    on_crash = opts.on_crash,
    method = "json-code-gen-v2",
    params = { filePath = file_path, jsonData = json_data, preferFileScopedNamespace = prefer_file_scoped },
  })()
end

function M:bootstrap_file_v2(file_path, type, prefer_file_scoped, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(res) cb(res.success) end,
    on_crash = opts.on_crash,
    method = "roslyn/bootstrap-file-v2",
    params = { filePath = file_path, kind = type, preferFileScopedNamespace = prefer_file_scoped },
  })()
end

---@param opts easy-dotnet.RPC.Client.NewFile.CreateItemOpts
---@return easy-dotnet.RPC.CallHandle
function M:create_item(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "new-file/create-item",
    params = {
      outputPath = opts.output_path,
      preferFileScopedNamespace = opts.prefer_file_scoped_namespace or false,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

return M
