---@class easy-dotnet.RPC.Client.UpgradeWizard
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field open fun(self: easy-dotnet.RPC.Client.UpgradeWizard, target_path: string, cb?: fun()): easy-dotnet.RPC.CallHandle
---@field apply fun(self: easy-dotnet.RPC.Client.UpgradeWizard, target_path: string, selections: table[], cb?: fun()): easy-dotnet.RPC.CallHandle
---@field cancel fun(self: easy-dotnet.RPC.Client.UpgradeWizard): easy-dotnet.RPC.CallHandle
---@field changelog fun(self: easy-dotnet.RPC.Client.UpgradeWizard, package_id: string, version: string, cb?: fun(result: easy-dotnet.ChangelogResult)): easy-dotnet.RPC.CallHandle
---@field versions fun(self: easy-dotnet.RPC.Client.UpgradeWizard, package_id: string, cb?: fun(result: string[])): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.UpgradeWizard
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@param target_path string
---@param cb? fun()
function M:open(target_path, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "nuget/upgradeWizard/open",
    params = { targetPath = target_path },
    cb = cb,
  })()
end

---@param target_path string
---@param selections table[]  UpgradeSelection objects (packageId, targetVersion, affectedProjects, isCentrallyManaged, currentVersion)
---@param cb? fun()
function M:apply(target_path, selections, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "nuget/upgradeWizard/apply",
    params = { targetPath = target_path, selections = selections },
    cb = cb,
  })()
end

---@param cb? fun()
function M:cancel(cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "nuget/upgradeWizard/cancel",
    params = {},
    cb = cb,
  })()
end

---@param package_id string
---@param version string
---@param cb? fun(result: easy-dotnet.ChangelogResult)
function M:changelog(package_id, version, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "nuget/upgradeWizard/changelog",
    params = { packageId = package_id, version = version },
    cb = cb,
  })()
end

---@param package_id string
---@param cb? fun(result: string[])
function M:versions(package_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "nuget/upgradeWizard/versions",
    params = { packageId = package_id },
    cb = cb,
  })()
end

return M
