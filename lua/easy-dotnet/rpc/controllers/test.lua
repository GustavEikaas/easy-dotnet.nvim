---@class easy-dotnet.RPC.Client.Test
---@field _client easy-dotnet.RPC.StreamJsonRpc
-- luacheck: no max line length
---@field test_run fun(self: easy-dotnet.RPC.Client.Test, request: easy-dotnet.RPC.TestRunRequest, cb?: fun(res: RPC_TestRunResult), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request running multiple tests for MTP
---@field test_debug fun(self: easy-dotnet.RPC.Client.Test, request: easy-dotnet.RPC.TestRunRequest, cb?: fun(res: RPC_TestRunResult), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request running multiple tests for MTP
-- luacheck: no max line length
---@field test_discover fun(self: easy-dotnet.RPC.Client.Test, request: easy-dotnet.RPC.TestDiscoverRequest, cb?: fun(res: easy-dotnet.RPC.DiscoveredTest[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle # Request test discovery for MTP
---@field test_solution fun(self: easy-dotnet.RPC.Client.Test, cb?: fun(res: easy-dotnet.Server.RunCommand), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field set_run_settings fun(self: easy-dotnet.RPC.Client.Test)

local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.Test
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

function M:test_debug(request, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    job = nil,
    method = "test/debug",
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

function M:set_run_settings() self._client.notify("test/set-project-run-settings", {}) end

function M:test_solution(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_rpc_call({
    client = self._client,
    cb = cb,
    on_crash = opts.on_crash,
    method = "test/solution-command",
    params = vim.empty_dict(),
  })()
end

return M
