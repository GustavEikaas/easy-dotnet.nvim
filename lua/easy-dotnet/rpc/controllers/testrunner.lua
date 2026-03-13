---@class easy-dotnet.RPC.Client.TestRunner
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field quick_discover fun(self: easy-dotnet.RPC.Client.TestRunner, solution_path: string, cb?: fun(result: table)): easy-dotnet.RPC.CallHandle
---@field initialize fun(self: easy-dotnet.RPC.Client.TestRunner, solution_path: string, cb?: fun(result: table)): easy-dotnet.RPC.CallHandle
---@field run fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult), source: string): easy-dotnet.RPC.CallHandle
---@field debug fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult), source: string): easy-dotnet.RPC.CallHandle
---@field invalidate fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult)): easy-dotnet.RPC.CallHandle
---@field get_results fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb: fun(result: easy-dotnet.TestRunner.Results)): easy-dotnet.RPC.CallHandle
---@field get_build_errors fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string): easy-dotnet.RPC.CallHandle
---@field sync_file fun(self: easy-dotnet.RPC.Client.TestRunner, path: string, content: string, version: integer, cb: fun(result: easy-dotnet.TestRunner.SyncFileResult)): easy-dotnet.RPC.CallHandle

---@class easy-dotnet.TestRunner.OperationResult
---@field success boolean

---@class easy-dotnet.TestRunner.Results
---@field found boolean
---@field errorMessage string[]|nil
---@field stdout string[]|nil
---@field frames easy-dotnet.TestRunner.StackFrame[]|nil
---@field failingFrame easy-dotnet.TestRunner.StackFrame|nil
---@field durationDisplay string|nil

---@class easy-dotnet.TestRunner.StackFrame
---@field originalText string
---@field file string|nil
---@field line integer|nil
---@field isUserCode boolean

---@class easy-dotnet.TestRunner.BuildErrorsResult
---@field errors easy-dotnet.TestRunner.BuildError[]

---@class easy-dotnet.TestRunner.BuildError
---@field filePath string|nil
---@field lineNumber integer|nil
---@field columnNumber integer|nil
---@field message string|nil

---@class easy-dotnet.TestRunner.SyncFileResult
---@field updates easy-dotnet.TestRunner.LineNumberUpdate[]
---@field version integer

---@class easy-dotnet.TestRunner.LineNumberUpdate
---@field id string
---@field signatureLine integer
---@field bodyStartLine integer
---@field endLine integer

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

function M:quick_discover(solution_path, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/quickDiscover",
    params = { solutionPath = solution_path },
    cb = cb,
  })()
end

---@param solution_path string
---@param cb? fun(result: table)
function M:initialize(solution_path, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/initialize",
    params = { solutionPath = solution_path },
    cb = cb,
  })()
end

---@param node_id string stable server-generated node ID
---@param cb? fun(result: table)
---@param source string where the run was initiated from (e.g. "testrunner"|"buffer")
function M:run(node_id, cb, source)
  assert(type(source) == "string", "testrunner/run requires source")
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/run",
    params = { id = node_id, source = source },
    cb = cb,
  })()
end

---@param node_id string
---@param cb? fun(result: table)
---@param source string where the debug was initiated from (e.g. "testrunner"|"buffer")
function M:debug(node_id, cb, source)
  assert(type(source) == "string", "testrunner/debug requires source")
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/debug",
    params = { id = node_id, source = source },
    cb = cb,
  })()
end

---@param node_id string
---@param cb? fun(result: table)
function M:invalidate(node_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/invalidate",
    params = { id = node_id },
    cb = cb,
  })()
end

---@param node_id string
---@param cb fun(result: easy-dotnet.TestRunner.Results)
function M:get_results(node_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/getResults",
    params = { id = node_id },
    cb = cb,
  })()
end

--- testrunner/syncFile — parse in-memory buffer content and update line numbers.
--- Called on BufWritePost for known test files. Version is a monotonic counter
--- per file — stale responses (version < latest sent) are discarded by the caller.
---@param path string absolute file path
---@param content string full buffer content joined with "\n"
---@param version integer monotonically increasing per-file counter
---@param cb fun(result: easy-dotnet.TestRunner.SyncFileResult)
function M:sync_file(path, content, version, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/syncFile",
    params = { path = path, content = content, version = version },
    cb = cb,
  })()
end

--- testrunner/getBuildErrors — tell the server to push build errors for a failed project node.
--- The server responds by sending a quickfix/set notification; no return value here.
--- The notification handler closes the test runner and opens the qf list automatically.
---@param node_id string
function M:get_build_errors(node_id)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/getBuildErrors",
    params = { id = node_id },
  })()
end

return M
