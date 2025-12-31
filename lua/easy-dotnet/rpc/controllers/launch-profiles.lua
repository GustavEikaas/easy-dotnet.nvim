---@class easy-dotnet.RPC.Client.LaunchProfiles
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field get_launch_profiles fun(self: easy-dotnet.RPC.Client.LaunchProfiles, target_path: string, cb?: fun(res: easy-dotnet.LaunchProfile.Response[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request msbuild

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.LaunchProfiles
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.LaunchProfile.Response
---@field name string
---@field value easy-dotnet.LaunchProfile.Profile

---@class easy-dotnet.LaunchProfile.Profile
---@field commandName? string
---@field dotnetRunMessages? boolean
---@field launchBrowser? boolean
---@field applicationUrl? string
---@field environmentVariables table<string, string> # like Dictionary<string,string>
---@field commandLineArgs? string
---@field workingDirectory? string

function M:get_launch_profiles(target_path, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "launch-profiles",
    params = { targetPath = target_path },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

return M
