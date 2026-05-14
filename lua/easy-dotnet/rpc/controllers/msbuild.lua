---@class easy-dotnet.RPC.Client.MsBuild
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field msbuild_query_properties fun(self: easy-dotnet.RPC.Client.MsBuild, request: easy-dotnet.MSBuild.QueryPropertiesRequest, cb?: fun(res: easy-dotnet.Project.Properties), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request msbuild
-- luacheck: no max line length
---@field msbuild_list_project_reference fun(self: easy-dotnet.RPC.Client.MsBuild, targetPath: string, cb?: fun(res: string[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request project references
-- luacheck: no max line length
---@field msbuild_list_package_reference fun(self: easy-dotnet.RPC.Client.MsBuild, targetPath: string, target_framework: string, cb?: fun(res: easy-dotnet.MSBuild.PackageReference[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request package references
-- luacheck: no max line length
---@field msbuild_add_project_reference fun(self: easy-dotnet.RPC.Client.MsBuild, projectPath: string, targetPath: string, cb?: fun(success: boolean), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request project references
-- luacheck: no max line length
---@field msbuild_remove_project_reference fun(self: easy-dotnet.RPC.Client.MsBuild, projectPath: string, targetPath: string, cb?: fun(success: boolean), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request project references

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.MsBuild
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.MSBuild.PackageReference
---@field id string
---@field requestedVersion string
---@field resolvedVersion string

---@class easy-dotnet.Project.Properties
---@field projectName string
---@field language string
---@field outputType? string
---@field targetFramework? string
---@field targetFrameworks? string[]
---@field isTestProject boolean
---@field isTestingPlatformApplication boolean
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field targetPath? string
---@field generatePackageOnBuild boolean
---@field isPackable boolean
---@field version? string
---@field isMultiTarget boolean
---@field useIISExpress boolean

---@class easy-dotnet.MSBuild.QueryPropertiesRequest
---@field targetPath string
---@field configuration? string
---@field targetFramework? string

function M:msbuild_query_properties(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local proj_name = vim.fn.fnamemodify(request.targetPath, ":t:r")
  return helper.create_rpc_call({
    client = self._client,
    job = { name = "Loading " .. proj_name, on_success_text = proj_name .. " loaded", on_error_text = "Failed to load " .. proj_name, timeout = -1 },
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/project-properties",
    params = { request = request },
  })()
end

function M:msbuild_list_project_reference(targetPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/list-project-reference",
    params = { projectPath = targetPath },
  })()
end

function M:msbuild_add_project_reference(projectPath, targetPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/add-project-reference",
    params = { projectPath = projectPath, targetPath = targetPath },
  })()
end

---@param projectPath string
---@param targetPath string
---@param cb? fun(success: boolean)
---@param opts? RPC_CallOpts
---@return easy-dotnet.RPC.CallHandle
function M:msbuild_remove_project_reference(projectPath, targetPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/remove-project-reference",
    params = { projectPath = projectPath, targetPath = targetPath },
  })()
end

function M:msbuild_list_package_reference(target_path, target_framework, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "msbuild/list-package-reference",
    params = { projectPath = target_path, targetFramework = target_framework },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

return M
