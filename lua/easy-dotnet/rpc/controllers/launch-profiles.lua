---@class LaunchProfilesClient
---@field _client StreamJsonRpc
---@field get_launch_profiles fun(self: LaunchProfilesClient, target_path: string, cb?: fun(res: LaunchProfileResponse[]), opts?: RPC_CallOpts): RPC_CallHandle # Request msbuild

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return LaunchProfilesClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class LaunchProfileResponse
---@field name string
---@field value LaunchProfile

---@class LaunchProfile
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
