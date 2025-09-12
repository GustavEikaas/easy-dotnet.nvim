local jobs = require("easy-dotnet.ui-modules.jobs")

---@class MsBuildClient
---@field _client StreamJsonRpc
---@field msbuild_query_properties fun(self: MsBuildClient, request: QueryProjectPropertiesRequest, cb?: fun(res: DotnetProjectProperties), opts?: RPC_CallOpts): RPC_CallHandle # Request msbuild
---@field msbuild_list_project_reference fun(self: MsBuildClient, targetPath: string, cb?: fun(res: string[]), opts?: RPC_CallOpts): RPC_CallHandle # Request project references
---@field msbuild_add_project_reference fun(self: MsBuildClient, projectPath: string, targetPath: string, cb?: fun(success: boolean), opts?: RPC_CallOpts): RPC_CallHandle # Request project references
---@field msbuild_remove_project_reference fun(self: MsBuildClient, projectPath: string, targetPath: string, cb?: fun(success: boolean), opts?: RPC_CallOpts): RPC_CallHandle # Request project references
---@field msbuild_build fun(self: MsBuildClient, request: BuildRequest, cb?: fun(res: BuildResult), opts?: RPC_CallOpts): RPC_CallHandle # Request msbuild

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return MsBuildClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class DotnetProjectProperties
---@field projectName string
---@field language string
---@field outputPath? string
---@field outputType? string
---@field targetExt? string
---@field assemblyName? string
---@field targetFramework? string
---@field targetFrameworks? string[]
---@field isTestProject boolean
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field userSecretsId? string
---@field testingPlatformDotnetTestSupport boolean
---@field targetPath? string
---@field generatePackageOnBuild boolean
---@field isPackable boolean
---@field langVersion? string
---@field rootNamespace? string
---@field packageId? string
---@field nugetVersion? string
---@field version? string
---@field packageOutputPath? string
---@field isMultiTarget boolean
---@field isNetFramework boolean
---@field useIISExpress boolean
---@field runCommand string
---@field buildCommand string
---@field testCommand string

---@class QueryProjectPropertiesRequest
---@field targetPath string
---@field configuration? string
---@field targetFramework? string

function M:msbuild_query_properties(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local proj_name = vim.fn.fnamemodify(request.targetPath, ":t:r")
  return helper.create_rpc_call({
    client = self._client,
    job = { name = "Loading " .. proj_name, on_success_text = proj_name .. " loaded", on_error_text = "Failed to load " .. proj_name },
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

---@param client StreamJsonRpc
---@param projectPath string
---@param targetPath string
---@param cb? fun(success: boolean)
---@param opts? RPC_CallOpts
---@return RPC_CallHandle
function M:msbuild_remove_project_reference(client, projectPath, targetPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/remove-project-reference",
    params = { projectPath = projectPath, targetPath = targetPath },
  })()
end

---@class BuildRequest
---@field targetPath string
---@field targetFramework? string
---@field configuration? string
---@field buildArgs? string

---@class Diagnostic
---@field code string
---@field columnNumber integer
---@field filePath string
---@field lineNumber integer
---@field message string
---@field type "error" | "warning"

---@class BuildResult
---@field errors Diagnostic[]
---@field warnings Diagnostic[]
---@field success boolean

function M:msbuild_build(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local finished = jobs.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(result)
      local pending = 2

      local function done()
        if pending == 0 then
          finished(result.success)
          if cb then cb(result) end
        end
      end

      if result.warnings and result.warnings.token then
        self._client:request_property_enumerate(result.warnings.token, nil, function(warnings)
          result.warnings = warnings
          pending = pending - 1
          done()
        end)
      end

      if result.errors and result.errors.token then
        self._client:request_property_enumerate(result.errors.token, nil, function(errors)
          result.errors = errors
          pending = pending - 1
          done()
        end)
      end
    end,
    on_crash = opts.on_crash,
    method = "msbuild/build",
    params = { request = request },
  })()
end

return M
