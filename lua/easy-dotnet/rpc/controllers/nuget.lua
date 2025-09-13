---@class NugetClient
---@field _client StreamJsonRpc
---@field nuget_restore fun(self: NugetClient, targetPath: string, cb?: fun(res: BuildResult), opts?: RPC_CallOpts): RPC_CallHandle # Request a NuGet restore
---@field nuget_search fun(self: NugetClient, searchTerm: string, sources?: string[], cb?: fun(res: NugetPackageMetadata[]), opts?: RPC_CallOpts): RPC_CallHandle # Request a NuGet restore
---@field nuget_get_package_versions fun(self: NugetClient, packageId: string, sources?: string[], include_prerelease?: boolean, cb?: fun(res: string[]), opts?: RPC_CallOpts): RPC_CallHandle # Request a NuGet restore
---@field nuget_push fun(self: NugetClient, packages: string[], source: string, cb?: fun(success: boolean), opts?: RPC_CallOpts): RPC_CallHandle # Request a NuGet restore

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

function M:nuget_push(packages, source, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = { name = "Pushing packages", on_error_text = "Failed to push packages", on_success_text = "Packages pushed to " .. source },
    cb = cb,
    on_crash = opts.on_crash,
    method = "nuget/push",
    params = { packagePaths = packages, source = source },
  })()
end

---@class RestoreResult
---@field errors Diagnostic[]
---@field warnings Diagnostic[]
---@field success boolean

function M:nuget_restore(targetPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = { name = "Restoring packages...", on_error_text = "Failed to restore nuget packages", on_success_text = "Nuget packages restored" },
    cb = function(result)
      local pending = 2

      local function done()
        if pending == 0 then
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
    method = "nuget/restore",
    params = { targetPath = targetPath },
  })()
end

---@class NugetPackageMetadata
---@field source string
---@field id string
---@field version string
---@field authors? string
---@field description? string
---@field downloadCount? integer
---@field licenseUrl? string
---@field owners string[]
---@field projectUrl? string
---@field readmeUrl? string
---@field summary? string
---@field tags string[]
---@field title? string
---@field prefixReserved boolean
---@field isListed boolean

function M:nuget_search(prompt, sources, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = { name = "Getting versions for " .. package, on_error_text = string.format("Failed to get versions for %s", package) },
    method = "nuget/search-packages",
    params = { searchTerm = prompt, sources = sources },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

function M:nuget_get_package_versions(package, sources, include_prerelease, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  include_prerelease = include_prerelease or false
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = { name = "Getting versions for " .. package, on_error_text = string.format("Failed to get versions for %s", package) },
    method = "nuget/get-package-versions",
    params = { packageId = package, includePrerelease = include_prerelease, sources = sources },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end
