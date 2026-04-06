---@class easy-dotnet.RPC.Client.ProjectReference
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field add_project_reference fun(self: easy-dotnet.RPC.Client.ProjectReference, projectPath: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Interactive add project reference — server handles scanning and picker
-- luacheck: no max line length
---@field remove_project_reference fun(self: easy-dotnet.RPC.Client.ProjectReference, projectPath: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Interactive remove project reference — server handles picker

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.ProjectReference
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:add_project_reference(projectPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/add-project-reference-interactive",
    params = { projectPath = projectPath },
  })()
end

function M:remove_project_reference(projectPath, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "msbuild/remove-project-reference-interactive",
    params = { projectPath = projectPath },
  })()
end

return M
