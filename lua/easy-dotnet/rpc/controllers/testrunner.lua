---@class easy-dotnet.RPC.Client.TestRunner
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field initialize fun(self: easy-dotnet.RPC.Client.TestRunner, solution_path: string, cb?: fun(result: table)): easy-dotnet.RPC.CallHandle
---@field run fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult)): easy-dotnet.RPC.CallHandle
---@field debug fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult)): easy-dotnet.RPC.CallHandle
---@field invalidate fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb?: fun(result: easy-dotnet.TestRunner.OperationResult)): easy-dotnet.RPC.CallHandle
---@field get_results fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb: fun(result: easy-dotnet.TestRunner.Results)): easy-dotnet.RPC.CallHandle
---@field get_build_errors fun(self: easy-dotnet.RPC.Client.TestRunner, node_id: string, cb: fun(result: easy-dotnet.TestRunner.BuildErrorsResult)): easy-dotnet.RPC.CallHandle

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

local M = {}
M.__index = M

---@param client easy-dotnet.RPC.StreamJsonRpc
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
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
function M:run(node_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/run",
    params = { id = node_id },
    cb = cb,
  })()
end

---@param node_id string
---@param cb? fun(result: table)
function M:debug(node_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/debug",
    params = { id = node_id },
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

---@param node_id string
---@param cb fun(result: easy-dotnet.TestRunner.BuildErrors)
function M:get_build_errors(node_id, cb)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  return helper.create_rpc_call({
    client = self._client,
    method = "testrunner/getBuildErrors",
    params = { id = node_id },
    cb = cb,
  })()
end

return M
