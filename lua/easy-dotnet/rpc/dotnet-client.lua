local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

---@type easy-dotnet.RPC.Client.Dotnet
local M = {}
M.__index = M

--- Handles an RPC response and displays/logs error info if present
---@param response easy-dotnet.RPC.Response
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

---@class easy-dotnet.RPC.CallOpts
---@field client easy-dotnet.RPC.StreamJsonRpc The RPC client object
---@field job? JobData Optional job function wrapper
---@field cb? fun(result: any) Callback function with RPC result
---@field on_crash? fun(err: easy-dotnet.RPC.Error) Optional crash callback
---@field method easy-dotnet.RPC.DotnetPipeMethod The RPC method to call
---@field params table Parameters for the RPC call

---@class easy-dotnet.RPC.CallHandle
---@field id number The RPC request ID
---@field cancel fun() Cancels the RPC request

---@param opts easy-dotnet.RPC.CallOpts
---@return fun():easy-dotnet.RPC.CallHandle
function M.create_rpc_call(opts)
  return function()
    local maybe_job = nil
    if opts.job then maybe_job = jobs.register_job(opts.job) end
    ---@param response easy-dotnet.RPC.Response
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

---@class easy-dotnet.RPC.EnumerateCallOpts
---@field client easy-dotnet.RPC.StreamJsonRpc The RPC client object
---@field job? JobData Optional job function wrapper
---@field cb? fun(result: any[]) Callback function with RPC result
---@field on_crash? fun(err: easy-dotnet.RPC.Error) Optional crash callback
---@field on_yield? fun(item: any)
---@field method easy-dotnet.RPC.DotnetPipeMethod The RPC method to call
---@field params table Parameters for the RPC call

---@param opts easy-dotnet.RPC.EnumerateCallOpts
---@return fun():easy-dotnet.RPC.CallHandle
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
      cancel = function()
        opts.client.cancel(id)
        if maybe_job then maybe_job(true) end
      end,
    }
  end
end

---@class easy-dotnet.RPC.CallOpts
---@field on_crash? fun(err: easy-dotnet.RPC.Error)

---@class easy-dotnet.RPC.Client.Dotnet
---@field new fun(self: easy-dotnet.RPC.Client.Dotnet): easy-dotnet.RPC.Client.Dotnet # Constructor
---@field initialized_msbuild_path string
---@field has_lsp boolean
---@field supports_single_file_execution boolean
---@field _client easy-dotnet.RPC.StreamJsonRpc # Underlying StreamJsonRpc client used for communication
---@field _server easy-dotnet.Server.Server # Manages the .NET named pipe server process
---@field initialize fun(self: easy-dotnet.RPC.Client.Dotnet, cb: fun()): nil # Starts the dotnet server and connects the JSON-RPC client
---@field stop fun(self: easy-dotnet.RPC.Client.Dotnet, cb: fun()): nil # Stops the dotnet server
---@field restart fun(self: easy-dotnet.RPC.Client.Dotnet, cb: fun()): nil # Restarts the dotnet server and connects the JSON-RPC client
---@field msbuild easy-dotnet.RPC.Client.MsBuild
---@field debugger easy-dotnet.RPC.Client.Debugger
---@field lsp easy-dotnet.RPC.Client.Lsp
---@field template_engine easy-dotnet.RPC.Client.TemplateEngine
---@field launch_profiles easy-dotnet.RPC.Client.LaunchProfiles
---@field nuget easy-dotnet.RPC.Client.Nuget
---@field roslyn easy-dotnet.RPC.Client.Roslyn
---@field test easy-dotnet.RPC.Client.Test
-- luacheck: no max line length
---@field secrets_init fun(self: easy-dotnet.RPC.Client.Dotnet, target_path: string, cb?: fun(res: easy-dotnet.RPC.ProjectUserSecretsInitResponse), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request adding package
-- luacheck: no max line length
---@field solution_list_projects fun(self: easy-dotnet.RPC.Client.Dotnet, solution_file_path: string, cb?: fun(res: easy-dotnet.Server.SolutionFileProjectResponse[]), include_non_existing?: boolean, opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field outdated_packages fun(self: easy-dotnet.RPC.Client.Dotnet, target_path: string, cb?: fun(res: easy-dotnet.Nuget.OutdatedPackage[])): integer | false # Query dotnet-outdated for outdated packages
---@field get_state fun(self: easy-dotnet.RPC.Client.Dotnet): '"Connected"'|'"Not connected"'|'"Starting"'|'"Stopped"' # Returns current connection state
---@field _initializing boolean? # True while initialization is in progress
---@field _initialized boolean? # True once initialization is complete
---@field _initialize fun(self: easy-dotnet.RPC.Client.Dotnet, cb?: fun(response: table), opts?: easy-dotnet.RPC.CallOpts) # Sends the "initialize" RPC request to the server
---@field _init_callbacks table<function> List of callback functions waiting for initialization to complete

--- Constructor
---@return easy-dotnet.RPC.Client.Dotnet
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
  instance.launch_profiles = require("easy-dotnet.rpc.controllers.launch-profiles").new(client)
  instance.nuget = require("easy-dotnet.rpc.controllers.nuget").new(client)
  instance.roslyn = require("easy-dotnet.rpc.controllers.roslyn").new(client)
  instance.debugger = require("easy-dotnet.rpc.controllers.debugger").new(client)
  instance.lsp = require("easy-dotnet.rpc.controllers.lsp").new(client)
  instance.test = require("easy-dotnet.rpc.controllers.test").new(client)
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

local function splitVersion(version)
  local parts = {}
  for num in version:gmatch("%d+") do
    table.insert(parts, tonumber(num))
  end
  return parts
end

local function compareVersions(a, b)
  local va = splitVersion(a)
  local vb = splitVersion(b)

  local maxLen = math.max(#va, #vb)
  for i = 1, maxLen do
    local ai = va[i] or 0
    local bi = vb[i] or 0
    if ai > bi then
      return 1
    elseif ai < bi then
      return -1
    end
  end
  return 0
end

local function has_lsp(version) return compareVersions(version, "2.3.0.0") >= 0 end

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
        self:_initialize(function(result)
          local routes = result.capabilities.routes
          self._client.routes = routes
          M.has_lsp = has_lsp(result.serverInfo.version)

          M.initialized_msbuild_path = result.toolPaths.msBuildPath
          M.supports_single_file_execution = result.capabilities.supportsSingleFileExecution or false

          self._initializing = false
          self._initialized = true

          for _, callback in ipairs(self._init_callbacks) do
            pcall(callback, result)
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

function M:_initialize(cb, opts)
  opts = opts or {}
  coroutine.wrap(function()
    local use_visual_studio = require("easy-dotnet.options").options.server.use_visual_studio == true
    local debugger_path = require("easy-dotnet.options").options.debugger.bin_path
    local apply_value_converters = require("easy-dotnet.options").options.debugger.apply_value_converters
    local sln_file = require("easy-dotnet.parsers.sln-parse").find_solution_file()

    local debuggerOptions = { applyValueConverters = apply_value_converters, binaryPath = debugger_path, externalOutputWindow = true }

    return M.create_rpc_call({
      client = self._client,
      job = { name = "Initializing...", on_success_text = "Client initialized", on_error_text = "Failed to initialize server" },
      cb = cb,
      on_crash = opts.on_crash,
      method = "initialize",
      params = {
        request = {
          clientInfo = { name = "EasyDotnet", version = "2.0.0" },
          projectInfo = { rootDir = vim.fs.normalize(vim.fn.getcwd()), solutionFile = sln_file },
          options = { useVisualStudio = use_visual_studio, debuggerOptions = debuggerOptions },
        },
      },
    })()
  end)()
end

---@class easy-dotnet.Server.SolutionFileProjectResponse
---@field projectName string
---@field absolutePath string

function M:solution_list_projects(solution_file_path, cb, include_non_existing, opts)
  include_non_existing = include_non_existing or false
  opts = opts or {}
  return M.create_rpc_call({
    client = self._client,
    job = nil,
    cb = function(res)
      local basename_solution = vim.fs.basename(solution_file_path)

      vim.iter(res):each(function(project)
        local ok = vim.fn.filereadable(project.absolutePath) == 1
        if not ok then logger.warn(string.format("%s references non existent project %s", basename_solution, vim.fs.basename(project.absolutePath))) end
      end)

      local filtered_projects = include_non_existing and res or vim.iter(res):filter(function(project) return vim.fn.filereadable(project.absolutePath) == 1 end):totable()

      cb(filtered_projects)
    end,
    on_crash = opts.on_crash,
    method = "solution/list-projects",
    params = { solutionFilePath = solution_file_path },
  })()
end

---@class easy-dotnet.RPC.ProjectUserSecretsInitResponse
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

---@class easy-dotnet.Nuget.OutdatedPackage
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

return M
