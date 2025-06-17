---@diagnostic disable: unused-function
local jobs = require("easy-dotnet.ui-modules.jobs")

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

-- --TODO: remove when server/client becomes 1.0.0
-- local function validate_routes(...)
--   local error_msg = "Server sent invalid initialize response; server might be outdated"
--
--   local arg1 = ({ ... })[1]
--   if type(arg1) ~= "table" then
--     vim.print(arg1)
--     error(error_msg .. ": first argument is not a table")
--   end
--
--   local result = arg1.result
--   if type(result) ~= "table" then
--     vim.print(arg1)
--     error(error_msg .. ": `result` is not a table")
--   end
--
--   local capabilities = result.capabilities
--   if type(capabilities) ~= "table" then
--     vim.print(arg1)
--     error(error_msg .. ": `capabilities` is not a table")
--   end
--
--   local routes = capabilities.routes
--   if type(routes) ~= "table" then
--     vim.print(arg1)
--     error(error_msg .. ": `routes` is not a table")
--   end
--
--   for _, route in ipairs(routes) do
--     if type(route) == "string" then return routes end
--   end
--
--   vim.print(arg1)
--   error(error_msg .. ": no valid routes found")
-- end

---@class DotnetClient
---@field new fun(self: DotnetClient): DotnetClient # Constructor
---@field _client StreamJsonRpc # Underlying StreamJsonRpc client used for communication
---@field _server DotnetServer # Manages the .NET named pipe server process
---@field initialize fun(self: DotnetClient, cb: fun()): nil # Starts the dotnet server and connects the JSON-RPC client
---@field stop fun(self: DotnetClient, cb: fun()): nil # Stops the dotnet server
---@field restart fun(self: DotnetClient, cb: fun()): nil # Restarts the dotnet server and connects the JSON-RPC client
---@field nuget_restore fun(self: DotnetClient, targetPath: string, cb?: fun(res: RPC_Response)) # Request a NuGet restore
---@field nuget_push fun(self: DotnetClient, packages: string[], source: string, cb?: fun(success: boolean)) # Request a NuGet restore
---@field msbuild_pack fun(self: DotnetClient, targetPath: string, configuration?: string, cb?: fun(res: RPC_Response)) # Request a NuGet restore
---@field msbuild_build fun(self: DotnetClient, request: BuildRequest, cb?: fun(res: RPC_Response)): integer|false # Request msbuild
---@field msbuild_query_properties fun(self: DotnetClient, request: QueryProjectPropertiesRequest, cb?: fun(res: RPC_Response)): integer|false # Request msbuild
---@field msbuild_add_package_reference fun(self: DotnetClient, request: AddPackageReferenceParams, cb?: fun(res: RPC_Response), options?: RpcRequestOptions): integer|false # Request adding package
---@field solution_list_projects fun(self: DotnetClient, solution_file_path: string, cb?: fun(res: SolutionFileProjectResponse[]), options?: RpcRequestOptions): integer|false # Request adding package
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

function M:stop(cb)
  assert(self._server, "[DotnetClient] .new() was not called before :stop(). Please construct with :new().")
  self._client.disconnect()
  self._server.stop()

  self._initialized = false
  self._initializing = false
  vim.defer_fn(function()
    if cb then cb() end
  end, 1000)
end

function M:restart(cb)
  self:stop(function() self:initialize(cb) end)
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
          -- TODO: start validating routes after "go live"
          -- local routes = validate_routes(...)
          -- self._client.routes = routes

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
  local finished = jobs.register_job({ name = "Initializing...", on_success_text = "Client initialized" })
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

function M:nuget_push(packages, source, cb)
  local finished = jobs.register_job({ name = "Pushing packages", on_error_text = "Failed to push packages", on_success_text = "Packages pushed to " .. source })
  self._client.request("nuget/push", { packagePaths = packages, source = source }, function(response)
    handle_rpc_error(response)
    finished(response.result.success)
    if cb then cb(response.result.success) end
  end)
end

function M:nuget_restore(targetPath, cb)
  local finished = jobs.register_job({ name = "Restoring packages...", on_error_text = "Failed to restore nuget packages", on_success_text = "Nuget packages restored" })
  self._client.request("msbuild/restore", { targetPath = targetPath }, function(response)
    handle_rpc_error(response)
    --TODO: check response body for success info
    finished(true)
    if cb then cb(response) end
  end)
end

function M:msbuild_pack(target_path, configuration, cb)
  local finished = jobs.register_job({ name = "Packing...", on_error_text = "Packing failed", on_success_text = "Packed successfully" })
  self._client.request("msbuild/pack", { targetPath = target_path, configuration = configuration }, function(response)
    handle_rpc_error(response)
    finished(response.result.success)
    if cb then cb(response) end
  end)
end

---@class AddPackageReferenceParams
---@field targetPath string
---@field packageName string
---@field version? string

function M:msbuild_add_package_reference(params, cb, options)
  local finished = jobs.register_job({
    name = "Adding package...",
    on_error_text = "Failed to add package",
    on_success_text = "Package added successfully",
  })

  local id = self._client.request("msbuild/add-package-reference", params, function(response)
    handle_rpc_error(response)
    finished(true)
    if cb then cb(response) end
  end, options)

  return id
end

---@class BuildRequest
---@field targetPath string
---@field configuration? string

function M:msbuild_build(request, cb)
  local finished = jobs.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })
  local id = self._client.request("msbuild/build", { request = request }, function(response)
    handle_rpc_error(response)
    --TODO: check response body for success info
    --TODO: open qf list
    finished(true)
    if cb then cb(response) end
  end)

  return id
end

---@class QueryProjectPropertiesRequest
---@field targetPath string
---@field configuration? string
---@field targetFramework? string

function M:msbuild_query_properties(request, cb)
  local id = self._client.request("msbuild/query-properties", { request = request }, function(response)
    handle_rpc_error(response)
    if cb then cb(response) end
  end)

  return id
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

---@class SolutionFileProjectResponse
---@field ProjectName string
---@field RelativePath string
---@field AbsolutePath string

function M:solution_list_projects(solution_file_path, cb)
  self._client.request("solution/list-projects", { solutionFilePath = solution_file_path }, function(response)
    handle_rpc_error(response)
    if cb then cb(response.result) end
  end)
end

return M
