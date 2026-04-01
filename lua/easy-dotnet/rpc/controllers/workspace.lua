---@class easy-dotnet.RPC.Client.Workspace
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field run fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.RunOpts): easy-dotnet.RPC.CallHandle
---@field debug fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.DebugOpts): easy-dotnet.RPC.CallHandle
---@field watch fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.WatchOpts): easy-dotnet.RPC.CallHandle
---@field build fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.BuildOpts): easy-dotnet.RPC.CallHandle
---@field restore fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.RestoreOpts): easy-dotnet.RPC.CallHandle
---@field build_solution fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.BuildSolutionOpts): easy-dotnet.RPC.CallHandle
---@field test fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.TestOpts): easy-dotnet.RPC.CallHandle
---@field test_solution fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.TestOpts): easy-dotnet.RPC.CallHandle

---@class easy-dotnet.RPC.Client.Workspace.RunOpts
---@field use_default boolean
---@field use_launch_profile boolean
---@field file_path string | nil
---@field cli_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.DebugOpts
---@field use_default boolean
---@field use_launch_profile boolean
---@field file_path string | nil
---@field cli_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.WatchOpts
---@field use_default boolean
---@field use_launch_profile boolean
---@field use_debugger boolean
---@field file_path string | nil
---@field cli_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.BuildOpts
---@field use_default boolean
---@field use_terminal boolean
---@field build_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.BuildSolutionOpts
---@field use_terminal boolean
---@field build_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.RestoreOpts
---@field restore_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Workspace.TestOpts
---@field use_default boolean
---@field test_args string | nil
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Workspace
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

--- Normalises a file_path hint: expands to absolute, clears it if not a .cs file.
---@param file_path string | nil
---@return string | nil
local function resolve_file_path(file_path)
  if not file_path then return nil end
  file_path = vim.fn.fnamemodify(file_path, ":p")
  if vim.fn.fnamemodify(file_path, ":e") ~= "cs" then return nil end
  return file_path
end

---@param opts easy-dotnet.RPC.Client.Workspace.RunOpts
---@return easy-dotnet.RPC.CallHandle
function M:run(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/run",
    params = {
      useDefault = opts.use_default or false,
      useLaunchProfile = opts.use_launch_profile or false,
      filePath = resolve_file_path(opts.file_path) or vim.NIL,
      cliArgs = opts.cli_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.DebugOpts
---@return easy-dotnet.RPC.CallHandle
function M:debug(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/debug",
    params = {
      useDefault = opts.use_default or false,
      useLaunchProfile = opts.use_launch_profile or false,
      filePath = resolve_file_path(opts.file_path) or vim.NIL,
      cliArgs = opts.cli_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.WatchOpts
---@return easy-dotnet.RPC.CallHandle
function M:watch(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/watch",
    params = {
      useDefault = opts.use_default or false,
      useLaunchProfile = opts.use_launch_profile or false,
      useDebugger = opts.use_debugger or false,
      filePath = resolve_file_path(opts.file_path) or vim.NIL,
      cliArgs = opts.cli_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.BuildOpts
---@return easy-dotnet.RPC.CallHandle
function M:build(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/build",
    params = {
      useDefault = opts.use_default or false,
      useTerminal = opts.use_terminal or false,
      buildArgs = opts.build_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.BuildSolutionOpts
---@return easy-dotnet.RPC.CallHandle
function M:build_solution(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/build-solution",
    params = {
      useDefault = false,
      useTerminal = opts.use_terminal or false,
      buildArgs = opts.build_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.RestoreOpts
---@return easy-dotnet.RPC.CallHandle
function M:restore(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/restore",
    params = {
      restoreArgs = opts.restore_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.TestOpts
---@return easy-dotnet.RPC.CallHandle
function M:test(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/test",
    params = {
      useDefault = opts.use_default or false,
      testArgs = opts.test_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

---@param opts easy-dotnet.RPC.Client.Workspace.TestOpts
---@return easy-dotnet.RPC.CallHandle
function M:test_solution(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/test-solution",
    params = {
      useDefault = false,
      testArgs = opts.test_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

return M
