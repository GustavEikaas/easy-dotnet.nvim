local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")

local function dump_to_file(obj, filepath)
  local serialized = vim.inspect(obj)
  local f = io.open(filepath, "w")
  if not f then error("Could not open file: " .. filepath) end
  f:write(serialized)
  f:close()
end

--- Handles an RPC response and displays/logs error info if present
---@param response RPC_Response
---@return boolean did_error
local function handle_rpc_error(response)
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
local function create_rpc_call(opts)
  return function()
    local maybe_job = nil
    if opts.job then maybe_job = jobs.register_job(opts.job) end
    ---@param response RPC_Response
    local id = opts.client.request(opts.method, opts.params, function(response)
      local crash = handle_rpc_error(response)
      if crash then
        if opts.on_crash then opts.on_crash(response.error) end
        if maybe_job then maybe_job(false) end
        return
      end

      if maybe_job then maybe_job(true) end
      if opts.cb then opts.cb(response.result) end
    end)
    if not id then error("Failed to send RPC call") end
    return {
      id = id,
      cancel = function() opts.client.cancel(id) end,
    }
  end
end

---@type DotnetClient
local M = {}
M.__index = M

---@class ProjectSecretInitResponse
---@field id string
---@field filePath string

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

---@class DotnetClient
---@field new fun(self: DotnetClient): DotnetClient # Constructor
---@field initialized_msbuild_path string
---@field _client StreamJsonRpc # Underlying StreamJsonRpc client used for communication
---@field _server DotnetServer # Manages the .NET named pipe server process
---@field initialize fun(self: DotnetClient, cb: fun()): nil # Starts the dotnet server and connects the JSON-RPC client
---@field stop fun(self: DotnetClient, cb: fun()): nil # Stops the dotnet server
---@field restart fun(self: DotnetClient, cb: fun()): nil # Restarts the dotnet server and connects the JSON-RPC client
---@field nuget_restore fun(self: DotnetClient, targetPath: string, cb?: fun(res: BuildResult)) # Request a NuGet restore
---@field nuget_search fun(self: DotnetClient, searchTerm: string, sources?: string[], cb?: fun(res: NugetPackageMetadata[])): integer | false # Request a NuGet restore
---@field nuget_get_package_versions fun(self: DotnetClient, packageId: string, sources?: string[], include_prerelease?: boolean, cb?: fun(res: string[])): integer | false # Request a NuGet restore
---@field nuget_push fun(self: DotnetClient, packages: string[], source: string, cb?: fun(success: boolean)) # Request a NuGet restore
---@field msbuild_pack fun(self: DotnetClient, targetPath: string, configuration?: string, cb?: fun(res: RPC_Response)) # Request a NuGet restore
---@field msbuild_build fun(self: DotnetClient, request: BuildRequest, cb?: fun(res: BuildResult)): integer|false # Request msbuild
---@field msbuild_query_properties fun(self: DotnetClient, request: QueryProjectPropertiesRequest, cb?: fun(res: DotnetProjectProperties), on_error?: fun(err: RPC_Error)): RPC_CallHandle # Request msbuild
---@field msbuild_list_project_reference fun(self: DotnetClient, targetPath: string, cb?: fun(res: string[]), on_crash?: fun(err: RPC_Error)): RPC_CallHandle # Request project references
---@field msbuild_add_project_reference fun(self: DotnetClient, projectPath: string, targetPath: string, cb?: fun(success: boolean), on_crash?: fun(err: RPC_Error)): RPC_CallHandle # Request project references
---@field msbuild_remove_project_reference fun(self: DotnetClient, projectPath: string, targetPath: string, cb?: fun(success: boolean)): integer|false # Request project references
---@field msbuild_add_package_reference fun(self: DotnetClient, request: AddPackageReferenceParams, cb?: fun(res: RPC_Response), options?: RpcRequestOptions): integer|false # Request adding package
---@field secrets_init fun(self: DotnetClient, target_path: string, cb?: fun(res: ProjectSecretInitResponse), options?: RpcRequestOptions): integer|false # Request adding package
---@field solution_list_projects fun(self: DotnetClient, solution_file_path: string, cb?: fun(res: SolutionFileProjectResponse[]), on_crash?: fun(err: RPC_Error), options?: RpcRequestOptions): RPC_CallHandle # Request adding package
---@field test_run fun(self: DotnetClient, request: RPC_TestRunRequest, cb?: fun(res: RPC_TestRunResult)) # Request running multiple tests for MTP
---@field test_discover fun(self: DotnetClient, request: RPC_TestDiscoverRequest, cb?: fun(res: RPC_DiscoveredTest[])) # Request test discovery for MTP
---@field outdated_packages fun(self: DotnetClient, target_path: string, cb?: fun(res: OutdatedPackage[])): integer | false # Query dotnet-outdated for outdated packages
---@field roslyn_bootstrap_file fun(self: DotnetClient, file_path: string, type: "Class" | "Interface" | "Record", prefer_file_scoped: boolean, cb?: fun(success: true)): integer | false
---@field roslyn_bootstrap_file_json fun(self: DotnetClient, file_path: string, json_data: string, prefer_file_scoped: boolean, cb?: fun(success: true)): integer | false
---@field roslyn_scope_variables fun(self: DotnetClient, file_path: string, line: number, cb?: fun(variables: VariableLocation[])): integer | false
---@field get_workspace_diagnostics fun(self: DotnetClient, project_path: string, include_warnings: boolean, cb?: fun(res: RPC_Response)): integer | false
---@field template_list fun(self: DotnetClient, cb?: fun(variables: DotnetNewTemplate[])): integer | false
---@field template_parameters fun(self: DotnetClient, identity: string, cb?: fun(variables: DotnetNewParameter[])): integer | false
---@field template_instantiate fun(self: DotnetClient, identity: string, name: string, output_path: string, params: table<string,string>, cb?: fun()): integer | false
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
      local crash = handle_rpc_error(response)
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

function M:nuget_push(packages, source, cb)
  local finished = jobs.register_job({ name = "Pushing packages", on_error_text = "Failed to push packages", on_success_text = "Packages pushed to " .. source })
  self._client.request("nuget/push", { packagePaths = packages, source = source }, function(response)
    local crash = handle_rpc_error(response)
    if crash then
      finished(false)
      return
    end
    finished(response.result.success)
    if cb then cb(response.result.success) end
  end)
end

function M:nuget_restore(targetPath, cb)
  local finished = jobs.register_job({ name = "Restoring packages...", on_error_text = "Failed to restore nuget packages", on_success_text = "Nuget packages restored" })
  self._client.request("nuget/restore", { targetPath = targetPath }, function(response)
    local crash = handle_rpc_error(response)
    if crash then
      finished(false)
      return
    end
    local result = response.result or {}
    local pending = 2

    local function done()
      if pending == 0 then
        finished(result.success)
        if cb then cb(result) end
      end
    end

    if result.warnings and result.warnings.token then
      self._client:request_property_enumerate(response.result.warnings.token, nil, function(warnings)
        response.result.warnings = warnings
        pending = pending - 1
        done()
      end)
    end

    if result.errors and result.errors.token then
      self._client:request_property_enumerate(response.result.errors.token, nil, function(errors)
        response.result.errors = errors
        pending = pending - 1
        done()
      end)
    end
  end)
end

---@class NugetPackageMetadata
---@field source string
---@field id string
---@field version string
---@field authors? string
---@field description? string
---@field downloadCount? integer
---@field licenseUrl? string
---@field owners string[]
---@field projectUrl? string
---@field readmeUrl? string
---@field summary? string
---@field tags string[]
---@field title? string
---@field prefixReserved boolean
---@field isListed boolean

function M:nuget_search(prompt, sources, cb)
  local id = self._client:request_enumerate("nuget/search-packages", { searchTerm = prompt, sources = sources }, nil, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb(response) end
  end, handle_rpc_error)

  return id
end

function M:nuget_get_package_versions(package, sources, include_prerelease, cb)
  local finished = jobs.register_job({ name = "Getting versions for " .. package, on_error_text = string.format("Failed to get versions for %s", package) })
  include_prerelease = include_prerelease or false
  local id = self._client:request_enumerate("nuget/get-package-versions", { packageId = package, includePrerelease = include_prerelease, sources = sources }, nil, function(response)
    finished(true)
    cb(response)
  end, function(res)
    handle_rpc_error(res)
    finished(false)
  end)
  return id
end

function M:msbuild_pack(target_path, configuration, cb)
  local finished = jobs.register_job({ name = "Packing...", on_error_text = "Packing failed", on_success_text = "Packed successfully" })
  self._client.request("msbuild/pack", { targetPath = target_path, configuration = configuration }, function(response)
    local crash = handle_rpc_error(response)
    if crash then
      finished(false)
      return
    end
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
    local crash = handle_rpc_error(response)
    if crash then
      finished(false)
      return
    end
    finished(true)
    if cb then cb(response) end
  end, options)

  return id
end

---@class BuildRequest
---@field targetPath string
---@field targetFramework? string
---@field configuration? string
---@field buildArgs? string

---@class Diagnostic
---@field code string
---@field columnNumber integer
---@field filePath string
---@field lineNumber integer
---@field message string
---@field type "error" | "warning"

---@class BuildResult
---@field errors Diagnostic[]
---@field warnings Diagnostic[]
---@field success boolean

function M:msbuild_build(request, cb)
  local finished = jobs.register_job({ name = "Building...", on_error_text = "Build failed", on_success_text = "Built successfully" })
  local id = self._client.request("msbuild/build", { request = request }, function(response)
    local crash = handle_rpc_error(response)
    if crash then
      finished(false)
      return
    end
    local result = response.result or {}
    local pending = 2

    local function done()
      if pending == 0 then
        finished(result.success)
        if cb then cb(result) end
      end
    end

    if result.warnings and result.warnings.token then
      self._client:request_property_enumerate(response.result.warnings.token, nil, function(warnings)
        response.result.warnings = warnings
        pending = pending - 1
        done()
      end)
    end

    if result.errors and result.errors.token then
      self._client:request_property_enumerate(response.result.errors.token, nil, function(errors)
        response.result.errors = errors
        pending = pending - 1
        done()
      end)
    end
  end)

  return id
end

---@class DotnetProjectProperties
---@field projectName string
---@field language string
---@field outputPath? string
---@field outputType? string
---@field targetExt? string
---@field assemblyName? string
---@field targetFramework? string
---@field targetFrameworks? string[]
---@field isTestProject boolean
---@field isWebProject boolean
---@field isWorkerProject boolean
---@field userSecretsId? string
---@field testingPlatformDotnetTestSupport boolean
---@field targetPath? string
---@field generatePackageOnBuild boolean
---@field isPackable boolean
---@field langVersion? string
---@field rootNamespace? string
---@field packageId? string
---@field nugetVersion? string
---@field version? string
---@field packageOutputPath? string
---@field isMultiTarget boolean
---@field isNetFramework boolean
---@field useIISExpress boolean
---@field runCommand string
---@field buildCommand string
---@field testCommand string

---@class QueryProjectPropertiesRequest
---@field targetPath string
---@field configuration? string
---@field targetFramework? string

function M:msbuild_query_properties(request, cb, on_crash)
  local proj_name = vim.fn.fnamemodify(request.targetPath, ":t:r")
  return create_rpc_call({
    client = self._client,
    job = { name = "Loading " .. proj_name, on_success_text = proj_name .. " loaded", on_error_text = "Failed to load " .. proj_name },
    cb = cb,
    on_crash = on_crash,
    method = "msbuild/project-properties",
    params = { request = request },
  })()
end

function M:msbuild_list_project_reference(targetPath, cb, on_crash)
  return create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = on_crash,
    method = "msbuild/list-project-reference",
    params = { projectPath = targetPath },
  })()
end

function M:msbuild_add_project_reference(projectPath, targetPath, cb, on_crash)
  return create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = on_crash,
    method = "msbuild/add-project-reference",
    params = { projectPath = projectPath, targetPath = targetPath },
  })()
end

function M:msbuild_remove_project_reference(projectPath, targetPath, cb)
  local id = self._client.request("msbuild/remove-project-reference", { projectPath = projectPath, targetPath = targetPath }, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result) end
  end)

  return id
end
function M:test_discover(request, cb) self._client:request_enumerate("test/discover", request, nil, cb, handle_rpc_error) end

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
  end, handle_rpc_error)
end

---@class SolutionFileProjectResponse
---@field projectName string
---@field relativePath string
---@field absolutePath string

function M:solution_list_projects(solution_file_path, cb, on_crash)
  return create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = on_crash,
    method = "solution/list-projects",
    params = { solutionFilePath = solution_file_path },
  })()
end

function M:secrets_init(project_path, cb)
  local id = self._client.request("user-secrets/init", { projectPath = project_path }, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result) end
  end)
  return id
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
    handle_rpc_error(res)
    on_job_finished(false)
  end)
  return id
end

function M:roslyn_bootstrap_file_json(file_path, json_data, prefer_file_scoped, cb)
  local id = self._client.request("json-code-gen", { filePath = file_path, jsonData = json_data, preferFileScopedNamespace = prefer_file_scoped }, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result.success) end
  end)
  return id
end

function M:roslyn_bootstrap_file(file_path, type, prefer_file_scoped, cb)
  local id = self._client.request("roslyn/bootstrap-file", { filePath = file_path, kind = type, preferFileScopedNamespace = prefer_file_scoped }, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb(response.result.success) end
  end)
  return id
end

function M:roslyn_scope_variables(file_path, line, cb)
  local id = self._client:request_enumerate("roslyn/scope-variables", { sourceFilePath = file_path, lineNumber = line }, nil, function(response) cb(response) end, handle_rpc_error)
  return id
end

---@class DotnetNewTemplate
---@field displayName string
---@field identity string
---@field type string|nil

function M:template_list(cb)
  local id = self._client:request_enumerate("template/list", {}, nil, function(response) cb(response) end, handle_rpc_error)
  return id
end

---@alias DotnetNewParameterDataType
---| '"text"'
---| '"bool"'
---| '"choice"'
---| '"string"'

---@class DotnetNewParameter
---@field name string
---@field defaultValue string|nil
---@field defaultIfOptionWithoutValue string|nil
---@field dataType DotnetNewParameterDataType
---@field description string|nil
---@field isRequired boolean
---@field choices table<string, string>|nil

function M:template_parameters(identity, cb)
  local id = self._client:request_enumerate("template/parameters", { identity = identity }, nil, function(response) cb(response) end, handle_rpc_error)
  return id
end

function M:template_instantiate(identity, name, output_path, params, cb)
  if #vim.tbl_keys(params) == 0 then params["_"] = "" end
  local id = self._client.request("template/instantiate", { identity = identity, name = name, outputPath = output_path, parameters = params }, function(response)
    local crash = handle_rpc_error(response)
    if crash then return end
    if cb then cb() end
  end)
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
      handle_rpc_error(error_response)
      finished(false)
    end
  )

  return id
end

return M
