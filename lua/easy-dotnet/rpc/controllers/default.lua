---@class easy-dotnet.RPC.Client.Default
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field set_default_startup_project fun(self: easy-dotnet.RPC.Client.Default, project_path: string, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field set_default_launch_profile fun(self: easy-dotnet.RPC.Client.Default, project_path: string, launch_profile: string, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field set_default_test_project fun(self: easy-dotnet.RPC.Client.Default, project_path: string, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field set_default_build_project fun(self: easy-dotnet.RPC.Client.Default, project_path: string, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field set_default_view_project fun(self: easy-dotnet.RPC.Client.Default, project_path: string, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Default
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:set_default_startup_project(project_path, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = function() end,
    on_crash = opts.on_crash,
    method = "set-default-startup-project",
    params = { projectPath = project_path },
  })()
end

function M:set_default_launch_profile(project_path, launch_profile, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = function() end,
    on_crash = opts.on_crash,
    method = "set-default-launch-profile",
    params = { projectPath = project_path, launchProfile = launch_profile },
  })()
end

function M:set_default_test_project(project_path, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = function() end,
    on_crash = opts.on_crash,
    method = "set-default-test-project",
    params = { projectPath = project_path },
  })()
end

function M:set_default_build_project(project_path, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = function() end,
    on_crash = opts.on_crash,
    method = "set-default-build-project",
    params = { projectPath = project_path },
  })()
end

function M:set_default_view_project(project_path, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = function() end,
    on_crash = opts.on_crash,
    method = "set-default-view-project",
    params = { projectPath = project_path },
  })()
end

return M
