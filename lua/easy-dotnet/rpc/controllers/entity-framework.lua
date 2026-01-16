---@class easy-dotnet.RPC.Client.EntityFramework
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field migration_add fun(self: easy-dotnet.RPC.Client.EntityFramework, migration_name: string | nil, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field migration_remove fun(self: easy-dotnet.RPC.Client.EntityFramework, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field migration_apply fun(self: easy-dotnet.RPC.Client.EntityFramework, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field database_update fun(self: easy-dotnet.RPC.Client.EntityFramework, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field database_drop fun(self: easy-dotnet.RPC.Client.EntityFramework, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.EntityFramework
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:migration_remove(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "ef/migrations-remove",
    params = {},
    cb = nil,
    on_crash = opts.on_crash,
  })()
end
function M:migration_add(migration_name, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "ef/migrations-add",
    params = { migrationName = migration_name or vim.NIL },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

function M:migration_apply(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "ef/migrations-apply",
    params = {},
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

function M:database_update(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "ef/database-update",
    params = {},
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

function M:database_drop(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "ef/database-drop",
    params = {},
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

return M
