---@class TestClient
---@field _client StreamJsonRpc
---@field test_run fun(self: TestClient, request: RPC_TestRunRequest, cb?: fun(res: RPC_TestRunResult), opts?: RPCCallOpts): RPC_CallHandle # Request running multiple tests for MTP
---@field test_discover fun(self: TestClient, request: RPC_TestDiscoverRequest, cb?: fun(res: RPC_DiscoveredTest[]), opts?: RPCCallOpts): RPC_CallHandle # Request test discovery for MTP

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return TestClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class RPC_DiscoveredTest
---@field id string
---@field namespace? string
---@field name string
---@field displayName string
---@field filePath string
---@field lineNumber? integer

---@class RPC_TestDiscoverRequest
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

---@class RunRequestNode
---@field uid string Unique test run identifier
---@field displayName string Human-readable name for the run

---@class RPC_TestRunRequest
---@field projectPath string
---@field targetFrameworkMoniker string
---@field configuration string
---@field filter? table<RunRequestNode>

--- @class RPC_TestRunResult
--- @field id string
--- @field stackTrace string[] | nil
--- @field message string | nil
--- @field outcome TestResult

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
      local pending = #res

      local function done()
        if pending == 0 then
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
            pending = pending - 1
            done()
          end)
        end
      end
    end,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

return M
