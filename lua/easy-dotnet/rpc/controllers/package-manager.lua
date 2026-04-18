---@class easy-dotnet.RPC.Client.PackageManager
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field add fun(self: easy-dotnet.RPC.Client.PackageManager, project_path?: string, include_prerelease?: boolean, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field remove fun(self: easy-dotnet.RPC.Client.PackageManager, project_path?: string, package_ids?: string[], cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field list_installed fun (self: easy-dotnet.RPC.Client.PackageManager, project_path: string, cb?: fun(res: easy-dotnet.PackageManager.InstalledPackageReference[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

---@class easy-dotnet.PackageManager.InstalledPackageReference
---@field id string
---@field version string

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.PackageManager
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@param project_path? string Optional .csproj path; skips project picker if set
---@param include_prerelease? boolean Include pre-release packages and versions (default: false)
---@param cb? fun()
---@param opts? easy-dotnet.RPC.CallOpts
---@return easy-dotnet.RPC.CallHandle
function M:add(project_path, include_prerelease, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  include_prerelease = include_prerelease or false
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "nuget/add-package",
    params = {
      projectPath = project_path or vim.NIL,
      includePrerelease = include_prerelease,
    },
    cb = cb,
    on_crash = opts.on_crash,
  })()
end

---@param project_path? string Optional .csproj path; skips project picker if set
---@param package_ids? string[] If set alongside project_path, skips package picker entirely
---@param cb? fun()
---@param opts? easy-dotnet.RPC.CallOpts
---@return easy-dotnet.RPC.CallHandle
function M:remove(project_path, package_ids, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "nuget/remove-package",
    params = {
      projectPath = project_path or vim.NIL,
      packageIds = package_ids or vim.NIL,
    },
    cb = cb,
    on_crash = opts.on_crash,
  })()
end

---@param project_path string
---@param cb? fun(res: easy-dotnet.PackageManager.InstalledPackageReference[])
---@param opts? easy-dotnet.RPC.CallOpts
---@return easy-dotnet.RPC.CallHandle
function M:list_installed(project_path, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "nuget/list-installed",
    params = { projectPath = project_path },
    cb = cb,
    on_crash = opts.on_crash,
  })()
end

return M
