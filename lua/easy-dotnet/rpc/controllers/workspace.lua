---@class easy-dotnet.RPC.Client.Workspace
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field run fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.RunOpts): easy-dotnet.RPC.CallHandle
---@field debug fun(self: easy-dotnet.RPC.Client.Workspace, opts: easy-dotnet.RPC.Client.Workspace.DebugOpts): easy-dotnet.RPC.CallHandle

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

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Workspace
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@param opts easy-dotnet.RPC.Client.Workspace.RunOpts
---@return easy-dotnet.RPC.CallHandle
function M:run(opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}

  local file_path = opts.file_path
  if file_path then
    file_path = vim.fn.fnamemodify(file_path, ":p")
    if vim.fn.fnamemodify(file_path, ":e") ~= "cs" then file_path = nil end
  end

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/run",
    params = {
      useDefault = opts.use_default or false,
      useLaunchProfile = opts.use_launch_profile or false,
      filePath = file_path or vim.NIL,
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

  local file_path = opts.file_path
  if file_path then
    file_path = vim.fn.fnamemodify(file_path, ":p")
    if vim.fn.fnamemodify(file_path, ":e") ~= "cs" then file_path = nil end
  end

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    method = "workspace/debug",
    params = {
      useDefault = opts.use_default or false,
      useLaunchProfile = opts.use_launch_profile or false,
      filePath = file_path or vim.NIL,
      cliArgs = opts.cli_args or vim.NIL,
    },
    cb = nil,
    on_crash = opts.on_crash,
  })()
end

return M
