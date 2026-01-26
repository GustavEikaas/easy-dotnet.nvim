---@class easy-dotnet.RPC.Client.TestRunner
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field test_run fun(self: easy-dotnet.RPC.Client.TestRunner, request: easy-dotnet.RPC.TestRunRequest, cb?: fun(res: RPC_TestRunResult), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Legacy Request running multiple tests for MTP
---@field test_discover fun(self: easy-dotnet.RPC.Client.TestRunner, request: easy-dotnet.RPC.TestDiscoverRequest, cb?: fun(res: easy-dotnet.RPC.DiscoveredTest[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Legacy Request test discovery for MTP
---@field test_runner_initialize fun(self: easy-dotnet.RPC.Client.TestRunner, solution_file_path: string, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field test_runner_discover fun(self: easy-dotnet.RPC.Client.TestRunner, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field run_tests fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string) # Fire-and-forget run request
---@field debug_test fun(self: easy-dotnet.RPC.Client.TestRunner, test_id: string, cb: fun(dap_config: table)) # Request debug config
---@field get_source_location fun(self: easy-dotnet.RPC.Client.TestRunner, test_id: string, cb: fun(location: { file: string, line: number })) # Request navigation info
---@field get_failure_info fun(self: easy-dotnet.RPC.Client.TestRunner, test_id: string, cb: fun(info: { stackTrace: string, message: string, stdOut: string })) # Request detailed failure info

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.TestRunner
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.RPC.DiscoveredTest
---@field id string
---@field namespace? string
---@field name string
---@field displayName string
---@field filePath string
---@field lineNumber? integer

---@class easy-dotnet.RPC.TestDiscoverRequest
---@field projectPath string
---@field targetFrameworkMoniker string
---@field configuration string

function M:test_discover(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "test/discover",
    params = request,
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

---@class easy-dotnet.RunRequestNode
---@field uid string Unique test run identifier
---@field displayName string Human-readable name for the run

---@class easy-dotnet.RPC.TestRunRequest
---@field projectPath string
---@field targetFrameworkMoniker string
---@field configuration string
---@field filter? table<easy-dotnet.RunRequestNode>

--- @class RPC_TestRunResult
--- @field id string
--- @field stackTrace string[] | nil
--- @field message string[] | nil
--- @field outcome TestResult
--- @field stdOut string[] | nil

function M:test_run(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "test/run",
    params = request,
    ---@param res RPC_TestRunResult[]
    cb = function(res)
      local stackTrace_pending = #res
      local stdOut_pending = #res

      local function done()
        if stackTrace_pending == 0 and stdOut_pending == 0 then
          if cb then cb(res) end
        end
      end
      done()

      for _, value in ipairs(res) do
        ---@diagnostic disable-next-line: undefined-field
        if value.stackTrace and value.stackTrace.token then
          ---@diagnostic disable-next-line: undefined-field
          self._client:request_property_enumerate(value.stackTrace.token, nil, function(trace)
            value.stackTrace = trace
            stackTrace_pending = stackTrace_pending - 1
            done()
          end)
        end

        ---@diagnostic disable-next-line: undefined-field
        if value.stdOut and value.stdOut.token then
          ---@diagnostic disable-next-line: undefined-field
          self._client:request_property_enumerate(value.stdOut.token, nil, function(output)
            value.stdOut = output
            stdOut_pending = stdOut_pending - 1
            done()
          end)
        end
      end
    end,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

function M:test_runner_initialize(sln, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "testrunner/initialize",
    params = {
      solutionFilePath = sln,
    },
  })()
end

function M:test_runner_discover(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "testrunner/discover",
    params = {},
  })()
end
function M:set_run_settings() self._client.notify("test/set-project-run-settings", {}) end

---Fire-and-forget run request. Server handles build, discovery, and execution.
---@param node_id string Node ID to run
function M:run_tests(node_id) self._client.notify("testrunner/run", { nodeId = node_id }) end

---Request debug configuration.
---@param test_id string
---@param cb fun(dap_config: table)
function M:debug_test(test_id, cb)
  -- Server builds project, finds output dll, and returns a DAP configuration object
  self._client.request("test/debug", { testId = test_id }, cb)
end

---Request navigation info.
---@param test_id string
---@param cb fun(location: { file: string, line: number })
function M:get_source_location(test_id, cb) self._client.request("testrunner/go-to-test-source", { nodeId = test_id }, cb) end

---Request detailed failure info (Stack trace, StdOut)
---@param test_id string
---@param cb fun(info: { stackTrace: string, message: string, stdOut: string })
function M:get_failure_info(test_id, cb) self._client.request("test/get-failure-info", { testId = test_id }, cb) end

return M
