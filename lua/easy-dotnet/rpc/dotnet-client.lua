local jobs = require("easy-dotnet.ui-modules.jobs")

---@class Options
---@field silence_errors? boolean

---@type DotnetClient
local M = {}
M.__index = M

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

--- Handles an RPC response and displays/logs error info if present
---@param response RPC_Response
local function handle_rpc_error(response)
  if response.error then
    vim.schedule(function() vim.notify(string.format("[RPC Error %s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)

    if response.error.data then
      local file = vim.fs.normalize(os.tmpname())
      dump_to_file(response, file)
      error("Crash dump written at " .. file)
    end
  end
end

---@class DotnetClient
---@field new fun(self: DotnetClient): DotnetClient # Constructor
---@field _client StreamJsonRpc # Underlying StreamJsonRpc client used for communication
---@field _server DotnetServer # Manages the .NET named pipe server process
---@field initialize fun(self: DotnetClient, cb: fun()): nil # Starts the dotnet server and connects the JSON-RPC client
---@field nuget_restore fun(self: DotnetClient, targetPath: string, cb?: fun(res: RPC_Response)) # Request a NuGet restore
---@field msbuild_build fun(self: DotnetClient, request: BuildRequest, cb?: fun(res: RPC_Response)) # Request msbuild
---@field vstest_discover fun(self: DotnetClient, request: VSTestDiscoverRequest, cb?: fun(res: RPC_Response)) # Request test discovery for vstest
---@field vstest_run fun(self: DotnetClient, request: VSTestRunRequest, cb?: fun(res: RPC_Response)) # Request running multiple tests for vstest
---@field mtp_run fun(self: DotnetClient, request: MtpRunRequest, cb?: fun(res: RPC_Response)) # Request running multiple tests for MTP
---@field mtp_discover fun(self: DotnetClient, request: MtpDiscoverRequest, cb?: fun(res: RPC_Response)) # Request test discovery for MTP
---@field get_state fun(self: DotnetClient): '"Connected"'|'"Not connected"'|'"Starting"'|'"Stopped"' # Returns current connection state
---@field _initializing boolean? # True while initialization is in progress
---@field _initialized boolean? # True once initialization is complete
---@field _initialize fun(self: DotnetClient, cb?: fun(response: RPC_Response)) # Sends the "initialize" RPC request to the server
---@field _init_callbacks table<function> List of callback functions waiting for initialization to complete

--- Constructor
---@return DotnetClient
function M:new()
  local instance = setmetatable({}, self)
  local client = require("easy-dotnet.rpc.rpc-client")
  client.subscribe_notifications(function(method, params) require("easy-dotnet.rpc.notification-handler").handler(instance, method, params) end)
  instance._client = client
  instance._server = require("easy-dotnet.rpc.server")
  instance._init_callbacks = {}
  instance._initializing = false
  instance._initialized = false
  return instance
end

function M:initialize(cb)
  assert(self._server, "[DotnetClient] .new() was not called before :initialize(). Please construct with :new().")

  if self._initializing then
    if cb then table.insert(self._init_callbacks, cb) end
    return
  end

  if self._initialized then
    if cb then vim.schedule(cb) end
    return
  end

  self._initializing = true
  self._init_callbacks = {}
  if cb then table.insert(self._init_callbacks, cb) end

  self._server.start(function()
    self._client.setup({ pipe_path = self._server.pipe_path, debug = false })
    self._client.connect(function()
      vim.schedule(function()
        self:_initialize(function(...)
          self._initializing = false
          self._initialized = true

          for _, callback in ipairs(self._init_callbacks) do
            pcall(callback, ...)
          end
          self._init_callbacks = {}
        end)
      end)
    end)
  end)
end

function M:get_state()
  if self._server then
    if self._server.ready then
      if self._client.is_connected() then
        return "Connected"
      else
        return "Not connected"
      end
    elseif self._server.is_negotiating then
      return "Starting"
    else
      return "Stopped"
    end
  else
    return "Stopped"
  end
end

function M:_initialize(cb)
  local finished = jobs.register_job({ name = "Initializing..." })
  self._client.request("initialize", {
    request = {
      clientInfo = { name = "EasyDotnet", version = "0.0.5" },
      projectInfo = { rootDir = vim.fs.normalize(vim.fn.getcwd()) },
    },
  }, function(response)
    handle_rpc_error(response)
    finished(true)
    if cb then cb(response) end
  end)
end

function M:nuget_restore(targetPath, cb)
  local finished = jobs.register_job({ name = "Restoring...", on_error_text = "Failed to restore nuget packages", on_success_text = "Nuget packages restored" })
  self._client.request("msbuild/restore", { targetPath = targetPath }, function(response)
    handle_rpc_error(response)
    --TODO: check response body for success info
    finished(true)
    if cb then cb(response) end
  end)
end

---@class BuildRequest
---@field targetPath string
---@field configuration? string

function M:msbuild_build(request, cb)
  local finished = jobs.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })
  self._client.request("msbuild/build", { request = request }, function(response)
    handle_rpc_error(response)
    --TODO: check response body for success info
    --TODO: open qf list
    finished(true)
    if cb then cb(response) end
  end)
end

---@class VSTestDiscoverRequest
---@field vsTestPath string
---@field dllPath string

function M:vstest_discover(request, cb)
  self._client.request("vstest/discover", request, function(response)
    handle_rpc_error(response)
    if cb then cb(response) end
  end)
end

---@class MtpDiscoverRequest
---@field testExecutablePath string

function M:mtp_discover(request, cb)
  self._client.request("mtp/discover", request, function(response)
    handle_rpc_error(response)
    if cb then cb(response) end
  end)
end

---@class VSTestRunRequest
---@field vsTestPath string
---@field dllPath string
---@field testIds string[]?

function M:vstest_run(request, cb)
  self._client.request("vstest/run", request, function(response)
    handle_rpc_error(response)
    if cb then cb(response) end
  end)
end

---@class RunRequestNode
---@field uid string Unique test run identifier
---@field displayName string Human-readable name for the run

---@class MtpRunRequest
---@field testExecutablePath string
---@field filter? table<RunRequestNode>

function M:mtp_run(request, cb)
  self._client.request("mtp/run", request, function(response)
    handle_rpc_error(response)
    if cb then cb(response) end
  end)
end

return M
