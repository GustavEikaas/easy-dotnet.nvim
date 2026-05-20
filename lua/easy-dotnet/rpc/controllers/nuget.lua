---@class easy-dotnet.RPC.Client.Nuget
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field nuget_search fun(self: easy-dotnet.RPC.Client.Nuget, searchTerm: string, sources?: string[], cb?: fun(res: easy-dotnet.Nuget.PackageMetadata[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request a NuGet restore
-- luacheck: no max line length
---@field nuget_get_package_versions fun(self: easy-dotnet.RPC.Client.Nuget, packageId: string, sources?: string[], include_prerelease?: boolean, cb?: fun(res: string[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request a NuGet restore

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Nuget
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.Nuget.PackageMetadata
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
    job = nil,
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

return M
