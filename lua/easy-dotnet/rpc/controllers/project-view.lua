---@class easy-dotnet.ProjectView.Action
---@alias easy-dotnet.ProjectView.ActionName "AddPackage"|"RemovePackage"|"UpdatePackage"|"AddProjectReference"|"RemoveProjectReference"|"Refresh"

---@class easy-dotnet.ProjectView.Header
---@field projectPath string
---@field name string
---@field version string|nil
---@field langVersion string|nil
---@field outputType string|nil
---@field targetFrameworks string[]
---@field availableActions easy-dotnet.ProjectView.ActionName[]

---@class easy-dotnet.ProjectView.Package
---@field id string
---@field version string
---@field isOutdated boolean
---@field latestVersion string|nil
---@field upgradeSeverity string|nil  "Major"|"Minor"|"Patch"|"None"|"Unknown"
---@field availableActions easy-dotnet.ProjectView.ActionName[]

---@class easy-dotnet.ProjectView.ProjectRef
---@field path string
---@field name string
---@field availableActions easy-dotnet.ProjectView.ActionName[]

---@class easy-dotnet.ProjectView.Snapshot
---@field header easy-dotnet.ProjectView.Header
---@field packages easy-dotnet.ProjectView.Package[]
---@field projectReferences easy-dotnet.ProjectView.ProjectRef[]

---@class easy-dotnet.RPC.Client.ProjectView
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field get fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb: fun(snapshot: easy-dotnet.ProjectView.Snapshot), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field add_package fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field remove_package fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, package_id: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field update_package fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, package_id: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field upgrade_package fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, package_id: string, version: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field check_outdated fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field upgrade_all_outdated fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field add_project_reference fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field remove_project_reference fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, target_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field refresh fun(self: easy-dotnet.RPC.Client.ProjectView, project_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.ProjectView
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

local function call(self, method, params, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    method = method,
    params = params,
    cb = cb,
    on_crash = opts.on_crash,
  })()
end

function M:get(project_path, cb, opts) return call(self, "projectview/get", { projectPath = project_path or vim.NIL }, cb, opts) end

function M:add_package(project_path, cb, opts) return call(self, "projectview/addPackage", { projectPath = project_path }, cb, opts) end

function M:remove_package(project_path, package_id, cb, opts) return call(self, "projectview/removePackage", { projectPath = project_path, packageId = package_id }, cb, opts) end

function M:update_package(project_path, package_id, cb, opts) return call(self, "projectview/updatePackage", { projectPath = project_path, packageId = package_id }, cb, opts) end

function M:upgrade_package(project_path, package_id, version, cb, opts)
  return call(self, "projectview/upgradePackage", { projectPath = project_path, packageId = package_id, version = version }, cb, opts)
end

function M:check_outdated(project_path, cb, opts) return call(self, "projectview/checkOutdated", { projectPath = project_path }, cb, opts) end

function M:upgrade_all_outdated(project_path, cb, opts) return call(self, "projectview/upgradeAllOutdated", { projectPath = project_path }, cb, opts) end

function M:add_project_reference(project_path, cb, opts) return call(self, "projectview/addProjectReference", { projectPath = project_path }, cb, opts) end

function M:remove_project_reference(project_path, target_path, cb, opts) return call(self, "projectview/removeProjectReference", { projectPath = project_path, targetPath = target_path }, cb, opts) end

function M:refresh(project_path, cb, opts) return call(self, "projectview/refresh", { projectPath = project_path }, cb, opts) end

return M
