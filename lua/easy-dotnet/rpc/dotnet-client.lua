local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

---@type DotnetClient
local M = {}
M.__index = M

--- Handles an RPC response and displays/logs error info if present
---@param response RPC_Response
---@return boolean did_error
function M.handle_rpc_error(response)
  if response.error then
    vim.schedule(function() vim.notify(string.format("[RPC Error %s]: %s", response.error.code, response.error.message), vim.log.levels.ERROR) end)

    if response.error.data then
      local file = vim.fs.normalize(os.tmpname())
      dump_to_file(response, file)
      logger.error("Crash dump written at " .. file)
      return true
    end

    return true
  end
  return false
end

---@class RPCCallOpts
---@field client StreamJsonRpc The RPC client object
---@field job? JobData Optional job function wrapper
---@field cb? fun(result: any) Callback function with RPC result
---@field on_crash? fun(err: RPC_Error) Optional crash callback
---@field method DotnetPipeMethod The RPC method to call
---@field params table Parameters for the RPC call

---@class RPC_CallHandle
---@field id number The RPC request ID
---@field cancel fun() Cancels the RPC request

---@param opts RPCCallOpts
---@return fun():RPC_CallHandle
function M.create_rpc_call(opts)
  return function()
    local maybe_job = nil
    if opts.job then maybe_job = jobs.register_job(opts.job) end
    ---@param response RPC_Response
    local id = opts.client.request(opts.method, opts.params, function(response)
      local crash = M.handle_rpc_error(response)
      if crash then
        if opts.on_crash then opts.on_crash(response.error) end
        if maybe_job then maybe_job(false) end
        return
      end

      if maybe_job then maybe_job(type(response.result.success) == "boolean" and response.result.success or true) end
      if opts.cb then opts.cb(response.result) end
    end)
    if not id then error("Failed to send RPC call") end
    return {
      id = id,
      cancel = function() opts.client.cancel(id) end,
    }
  end
end

---@class RPC_EnumerateCallOpts
---@field client StreamJsonRpc The RPC client object
---@field job? JobData Optional job function wrapper
---@field cb? fun(result: any[]) Callback function with RPC result
---@field on_crash? fun(err: RPC_Error) Optional crash callback
---@field on_yield? fun(item: any)
---@field method DotnetPipeMethod The RPC method to call
---@field params table Parameters for the RPC call

---@param opts RPC_EnumerateCallOpts
---@return fun():RPC_CallHandle
function M.create_enumerate_rpc_call(opts)
  return function()
    local maybe_job = nil
    if opts.job then maybe_job = jobs.register_job(opts.job) end
    local id = opts.client:request_enumerate(opts.method, opts.params, opts.on_yield, function(results)
      if maybe_job then maybe_job(true) end
      if opts.cb then opts.cb(results) end
    end, function(res)
      if maybe_job then maybe_job(false) end
      if opts.on_crash then opts.on_crash(res.error) end
    end)
    if not id then error("Failed to send RPC call") end
    return {
      id = id,
      cancel = function() opts.client.cancel(id) end,
    }
  end
end

--- @class RPC_TestRunResult
--- @field id string
--- @field stackTrace string[] | nil
--- @field message string | nil
--- @field outcome TestResult

---@class RPC_DiscoveredTest
---@field id string
---@field namespace? string
---@field name string
---@field displayName string
---@field filePath string
---@field lineNumber? integer

---@class VariableLocation
---@field columnEnd integer
---@field columnStart integer
---@field identifier string
---@field lineEnd integer
---@field lineStart integer

---@class RPC_CallOpts
---@field on_crash? fun(err: RPC_Error)

---@class DotnetClient
---@field new fun(self: DotnetClient): DotnetClient # Constructor
---@field initialized_msbuild_path string
---@field _client StreamJsonRpc # Underlying StreamJsonRpc client used for communication
---@field _server DotnetServer # Manages the .NET named pipe server process
---@field initialize fun(self: DotnetClient, cb: fun()): nil # Starts the dotnet server and connects the JSON-RPC client
---@field stop fun(self: DotnetClient, cb: fun()): nil # Stops the dotnet server
---@field restart fun(self: DotnetClient, cb: fun()): nil # Restarts the dotnet server and connects the JSON-RPC client
---@field msbuild MsBuildClient
---@field template_engine TemplateEngineClient
---@field nuget NugetClient
---@field secrets_init fun(self: DotnetClient, target_path: string, cb?: fun(res: RPC_ProjectUserSecretsInitResponse), opts?: RPC_CallOpts): RPC_CallHandle # Request adding package
---@field solution_list_projects fun(self: DotnetClient, solution_file_path: string, cb?: fun(res: SolutionFileProjectResponse[]), opts?: RPC_CallOpts): RPC_CallHandle # Request adding package
---@field test_run fun(self: DotnetClient, request: RPC_TestRunRequest, cb?: fun(res: RPC_TestRunResult)) # Request running multiple tests for MTP
---@field test_discover fun(self: DotnetClient, request: RPC_TestDiscoverRequest, cb?: fun(res: RPC_DiscoveredTest[])) # Request test discovery for MTP
---@field outdated_packages fun(self: DotnetClient, target_path: string, cb?: fun(res: OutdatedPackage[])): integer | false # Query dotnet-outdated for outdated packages
---@field roslyn_bootstrap_file fun(self: DotnetClient, file_path: string, type: "Class" | "Interface" | "Record", prefer_file_scoped: boolean, cb?: fun(success: true)): integer | false
---@field roslyn_bootstrap_file_json fun(self: DotnetClient, file_path: string, json_data: string, prefer_file_scoped: boolean, cb?: fun(success: true)): integer | false
---@field roslyn_scope_variables fun(self: DotnetClient, file_path: string, line: number, cb?: fun(variables: VariableLocation[])): integer | false
---@field get_workspace_diagnostics fun(self: DotnetClient, project_path: string, include_warnings: boolean, cb?: fun(res: RPC_Response)): integer | false
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
  instance.msbuild = require("easy-dotnet.rpc.controllers.msbuild").new(client)
  instance.template_engine = require("easy-dotnet.rpc.controllers.template").new(client)
  instance.nuget = require("easy-dotnet.rpc.controllers.nuget").new(client)
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
          local routes = ({ ... })[1].result.capabilities.routes
          self._client.routes = routes

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
  coroutine.wrap(function()
    local finished = jobs.register_job({ name = "Initializing...", on_success_text = "Client initialized", on_error_text = "Failed to initialize server" })
    local use_visual_studio = require("easy-dotnet.options").options.server.use_visual_studio == true
    local sln_file = require("easy-dotnet.parsers.sln-parse").find_solution_file()
    self._client.request("initialize", {
      request = {
        clientInfo = { name = "EasyDotnet", version = "2.0.0" },
        projectInfo = { rootDir = vim.fs.normalize(vim.fn.getcwd()), solutionFile = sln_file },
        options = { useVisualStudio = use_visual_studio },
      },
    }, function(response)
      local crash = M.handle_rpc_error(response)
      if crash then
        finished(false)
        return
      end
      finished(true)
      M.initialized_msbuild_path = response.result.toolPaths.msBuildPath
      if cb then cb(response) end
    end)
  end)()
end

function M:test_discover(request, cb) self._client:request_enumerate("test/discover", request, nil, cb, M.handle_rpc_error) end

---@class RPC_TestDiscoverRequest
---@field projectPath string
---@field targetFrameworkMoniker string
---@field configuration string

---@class RunRequestNode
---@field uid string Unique test run identifier
---@field displayName string Human-readable name for the run

---@class RPC_TestRunRequest
---@field projectPath string
---@field targetFrameworkMoniker string
---@field configuration string
---@field filter? table<RunRequestNode>

function M:test_run(request, cb)
  self._client:request_enumerate("test/run", request, nil, function(res)
    local pending = #res

    local function done()
      if pending == 0 then
        if cb then cb(res) end
      end
    end
    done()

    for _, value in ipairs(res) do
      if value.stackTrace and value.stackTrace.token then
        self._client:request_property_enumerate(value.stackTrace.token, nil, function(trace)
          value.stackTrace = trace
          pending = pending - 1
          done()
        end)
      end
    end
  end, M.handle_rpc_error)
end

---@class SolutionFileProjectResponse
---@field projectName string
---@field relativePath string
---@field absolutePath string

function M:solution_list_projects(solution_file_path, cb, opts)
  opts = opts or {}
  return M.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "solution/list-projects",
    params = { solutionFilePath = solution_file_path },
  })()
end

---@class RPC_ProjectUserSecretsInitResponse
---@field id string
---@field filePath string

function M:secrets_init(project_path, cb, opts)
  opts = opts or {}
  return M.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "user-secrets/init",
    params = { projectPath = project_path },
  })()
end

---@class OutdatedPackage
---@field name string
---@field currentVersion string
---@field latestVersion string
---@field isOutdated boolean
---@field isTransitive boolean
---@field targetFramework string
---@field upgradeSeverity "None" | "Patch" | "Minor" | "Major" | "Unknown"

function M:outdated_packages(target_path, cb)
  local on_job_finished =
    require("easy-dotnet.ui-modules.jobs").register_job({ name = "Checking package references", on_success_text = "Outdated packages checked", on_error_text = "Checking package references failed" })
  local id = self._client:request_enumerate("outdated/packages", { targetPath = target_path, includeTransitive = false }, nil, function(results)
    on_job_finished(true)
    cb(results)
  end, function(res)
    M.handle_rpc_error(res)
    on_job_finished(false)
  end)
  return id
end

function M:roslyn_bootstrap_file_json(file_path, json_data, prefer_file_scoped, cb)
  local id = self._client.request("json-code-gen", { filePath = file_path, jsonData = json_data, preferFileScopedNamespace = prefer_file_scoped }, function(response)
    local crash = M.handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result.success) end
  end)
  return id
end

function M:roslyn_bootstrap_file(file_path, type, prefer_file_scoped, cb)
  local id = self._client.request("roslyn/bootstrap-file", { filePath = file_path, kind = type, preferFileScopedNamespace = prefer_file_scoped }, function(response)
    local crash = M.handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result.success) end
  end)
  return id
end

function M:roslyn_scope_variables(file_path, line, cb)
  local id = self._client:request_enumerate("roslyn/scope-variables", { sourceFilePath = file_path, lineNumber = line }, nil, function(response) cb(response) end, M.handle_rpc_error)
  return id
end

function M:get_workspace_diagnostics(project_path, include_warnings, cb)
  local finished = jobs.register_job({
    name = "Getting workspace diagnostics...",
    on_error_text = "Failed to get diagnostics",
    on_success_text = "Diagnostics retrieved",
  })

  local id = self._client:request_enumerate(
    "roslyn/get-workspace-diagnostics",
    {
      targetPath = project_path,
      includeWarnings = include_warnings,
    },
    nil,
    function(response)
      finished(true)
      if cb then cb(response) end
    end,
    function(error_response)
      M.handle_rpc_error(error_response)
      finished(false)
    end
  )

  return id
end

return M
