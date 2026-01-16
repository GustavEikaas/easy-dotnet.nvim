local logger = require("easy-dotnet.logger")
---@type easy-dotnet.RPC.StreamJsonRpc
local M = {
  routes = { "initialize" },
}

---@meta

---@class easy-dotnet.RPC.RequestOptions
---@field on_cancel? fun(): nil  -- optional callback for cancellation

---@class easy-dotnet.RPC.StreamJsonRpc
---@field _enumerable_next fun (token: integer, cb): nil
---@field setup fun(opts: { pipe_path: string, debug?: boolean }): easy-dotnet.RPC.StreamJsonRpc
---@field connect fun(cb: fun()): nil
-- luacheck: no max line length
---@field request fun(method: easy-dotnet.RPC.DotnetPipeMethod, params: table, callback: fun(result: easy-dotnet.RPC.Response), options?: RpcRequestOptions): integer|false
-- luacheck: no max line length
---@field request_enumerate fun(self: easy-dotnet.RPC.StreamJsonRpc, method: easy-dotnet.RPC.DotnetPipeMethod, params: table, on_yield: fun(result: table)|nil, on_finished: fun(results: table[])|nil, on_error: fun(res: easy-dotnet.RPC.Response)|nil): integer|false
---@field request_property_enumerate fun(self: easy-dotnet.RPC.StreamJsonRpc, token: string, on_yield: fun(result: table)|nil, on_finished: fun(results: table[])|nil, on_error: fun(res: easy-dotnet.RPC.Response)|nil): nil
---@field notify fun(method: string, params: table): boolean
---@field cancel fun(id: integer): nil
---@field disconnect fun(): boolean
---@field is_connected fun(): boolean
---@field subscribe_notifications fun(cb: easy-dotnet.RPC.NotificationCallback): fun(): nil
---@field routes table<string>? List of routes broadcasted by server

---@class easy-dotnet.RPC.Error
---@field code number
---@field message string
---@field data? RPC_Error_Stack

---@class easy-dotnet.RPC.ErrorStack
---@field type string
---@field message string
---@field stack string
---@field code number

---@class easy-dotnet.RPC.Response
---@field id number
---@field jsonrpc "2.0"
---@field result? table
---@field error? RPC_Error

---@class easy-dotnet.RPC.JsonRpcNotification
---@field jsonrpc "2.0"
---@field method string
---@field params? any

---@class easy-dotnet.RPC.PromptSelection
---@field id string
---@field display string

---@alias easy-dotnet.RPC.NotificationCallback fun(method: string, params: any | nil): nil

---@alias easy-dotnet.RPC.DotnetPipeMethod
---| "initialize"
---| "debugger/start"
---| "lsp/start"
---| "msbuild/build"
---| "launch-profiles"
---| "nuget/restore"
---| "msbuild/pack"
---| "msbuild/list-package-reference"
---| "msbuild/list-project-reference"
---| "msbuild/add-project-reference"
---| "msbuild/remove-project-reference"
---| "user-secrets/init"
---| "msbuild/project-properties"
---| "msbuild/add-package-reference"
---| "solution/list-projects"
---| "nuget/push"
---| "nuget/get-package-versions"
---| "nuget/search-packages"
---| "nuget/list-sources"
---| "test/discover"
---| "test/run"
---| "outdated/packages"
---| "roslyn/bootstrap-file"
---| "roslyn/scope-variables"
---| "roslyn/get-workspace-diagnostics"
---| "json-code-gen"
---| "template/list"
---| "template/parameters"
---| "template/instantiate"
---| "$/enumerator/next"

local connection = nil
local is_connected = false
local pipe_path = nil
local request_id = 0
local callbacks = {}
local cancellation_callbacks = {}

---@type easy-dotnet.RPC.NotificationCallback[]
local notification_callbacks = {}

---Initializes the StreamJsonRpc client with configuration.
---@param opts { pipe_path: string, debug?: boolean }
---@return easy-dotnet.RPC.StreamJsonRpc
function M.setup(opts)
  opts = opts or {}
  pipe_path = opts.pipe_path

  if not pipe_path then error("StreamJsonRpc client: pipe_path is required") end

  return M
end

---Encodes a Lua table into a JSON-RPC message with headers
---@param message table The JSON-RPC message body (already containing jsonrpc, id, etc.)
---@return string full_message The complete message (headers + JSON)
local function encode_rpc_message(message)
  local json_message = vim.json.encode(message)
  local header = string.format("Content-Length: %d\r\n\r\n", #json_message)
  return header .. json_message
end

local handlers = {
  openBuffer = require("easy-dotnet.rpc.handlers.open_buffer"),
  setBreakpoint = require("easy-dotnet.rpc.handlers.set_breakpoint"),
  promptConfirm = require("easy-dotnet.rpc.handlers.prompt_confirm"),
  promptString = require("easy-dotnet.rpc.handlers.prompt_string"),
  promptSelection = require("easy-dotnet.rpc.handlers.prompt_selection"),
  promptMultiSelection = require("easy-dotnet.rpc.handlers.prompt_selections"),
  startDebugSession = require("easy-dotnet.rpc.handlers.start_debug_session"),
  terminateDebugSession = require("easy-dotnet.rpc.handlers.terminate_debug_session"),
  runCommand = require("easy-dotnet.rpc.handlers.run_command"),
}

---Handles a server-initiated RPC request using a registered handler.
---@param decoded table The decoded JSON-RPC message
---@param response fun(result: any, err?: string|table) Response callback
---@param handler fun(params: table, respond: fun(any), throw: fun(any), validate: fun(any)) The handler function
local function handle_server_request(decoded, response, handler)
  local params = decoded.params or {}

  local validator = function(rules) return require("easy-dotnet.rpc.handlers.validator").validate_params(params, rules) end
  local throw = function(err) response(nil, err) end

  if handler then handler(params, response, throw, validator) end
end

---Create a response function for replying to server requests
---@param decoded table The original request object from the server
---@return fun(result: any, err?: string|table): nil
local function make_response(decoded)
  return function(result, err)
    if not connection then
      logger.error("RPC: cannot send response, no active connection")
      return
    end

    local message = {
      jsonrpc = "2.0",
      id = decoded.id,
    }

    if err then
      message.error = type(err) == "table" and err or { code = -32603, message = tostring(err) }
    else
      message.result = result
    end

    local full_message = encode_rpc_message(message)

    local ok, write_result = pcall(vim.loop.write, connection, full_message)
    if not ok or not write_result then vim.schedule(function() vim.notify("StreamJsonRpc: failed to send response for ID " .. tostring(decoded.id), vim.log.levels.ERROR) end) end
  end
end

local function handle_server_response(decoded)
  local cb = callbacks[decoded.id]
  if cb then
    callbacks[decoded.id] = nil
    cancellation_callbacks[decoded.id] = nil
    vim.schedule(function() cb(decoded) end)
  end
end

---Dispatches JSON-RPC notifications to all subscribed callbacks.
---@param decoded easy-dotnet.RPC.JsonRpcNotification
local function handle_server_notification(decoded)
  vim.schedule(function()
    for _, cb in ipairs(notification_callbacks) do
      pcall(cb, decoded.method, decoded.params)
    end
  end)
end

local function dispatch_server_request(decoded)
  local handler = handlers[decoded.method]
  if handler then
    vim.schedule(function() handle_server_request(decoded, make_response(decoded), handler) end)
  else
    logger.warn("Server sent unknown method: " .. tostring(decoded.method))
  end
end

---Starts reading from the JSON-RPC pipe and dispatching messages.
local function read_loop()
  local buffer = ""

  local function process_buffer()
    while true do
      local header_end = buffer:find("\r\n\r\n", 1, true)
      if not header_end then return end

      local header_section = buffer:sub(1, header_end - 1)
      local content_length = header_section:match("Content%-Length:%s*(%d+)")
      if not content_length then
        vim.notify("Missing Content-Length header", vim.log.levels.WARN)
        buffer = buffer:sub(header_end + 4)
        return
      end

      content_length = tonumber(content_length)
      local body_start = header_end + 4
      local body_end = body_start + content_length - 1

      if #buffer < body_end then return end

      local body = buffer:sub(body_start, body_end)
      buffer = buffer:sub(body_end + 1)

      local ok, decoded = pcall(vim.json.decode, body)
      if ok and decoded then
        if decoded.method and decoded.id then
          dispatch_server_request(decoded)
        elseif decoded.method and not decoded.id then
          handle_server_notification(decoded)
        elseif not decoded.method and decoded.id then
          handle_server_response(decoded)
        else
          logger.warn("Received invalid JSON-RPC message structure")
        end
      else
        vim.notify("Malformed JSON body: " .. body, vim.log.levels.WARN)
      end
    end
  end

  connection:read_start(function(err, data)
    if err then
      vim.schedule(function() vim.notify("Pipe read error: " .. err, vim.log.levels.ERROR) end)
      return
    end
    if data then
      buffer = buffer .. data
      process_buffer()
    end
  end)
end

---Connects to the RPC pipe and starts listening for messages.
---@param cb fun() Called when connection is established (or fail
function M.connect(cb)
  if is_connected and connection then cb() end
  if not pipe_path then error("StreamJsonRpc client: setup() must be called before connect()") end

  local pipe = vim.loop.new_pipe(false)

  if not pipe then
    vim.notify("StreamJsonRpc client: failed to create pipe", vim.log.levels.ERROR)
    cb()
  end

  connection = pipe
  pipe:connect(pipe_path, function(err)
    if err then
      vim.schedule(function() vim.notify("Failed to connect: " .. err, vim.log.levels.ERROR) end)
      cb()
      return
    end
    read_loop()
    cb()
    is_connected = true
  end)
end

---Sends a JSON-RPC request to the server.
---@param method easy-dotnet.RPC.DotnetPipeMethod
---@param params table
---@param callback fun(result: easy-dotnet.RPC.Response)
---@param options? RpcRequestOptions
---@return integer|false request_id or false if failed
function M.request(method, params, callback, options)
  options = options or {}
  if not vim.tbl_contains(M.routes, method) and method ~= "$/enumerator/next" then
    logger.warn("Server does not broadcast support for " .. method .. " perhaps your server is outdated? :Dotnet _server update")
  end
  if not is_connected then error("Client not connected") end

  request_id = request_id + 1
  local id = "c-" .. tostring(request_id)

  local message = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  callbacks[id] = callback
  cancellation_callbacks[id] = options.on_cancel

  local full_message = encode_rpc_message(message)

  local ok, write_result = pcall(vim.loop.write, connection, full_message)

  if not ok or not write_result then
    callbacks[id] = nil
    cancellation_callbacks[id] = nil
    if callback then vim.schedule(function() callback(nil) end) end
    return false
  end

  return id
end

function M:request_enumerate(method, params, on_yield, on_finished, on_error)
  local all_results = {}

  local function handle_next(token)
    self._enumerable_next(token, function(res)
      if res.error and on_error then on_error(res) end
      if res.result then
        if #res.result.values > 0 then
          vim.list_extend(all_results, res.result.values)
          if on_yield then on_yield(res.result.values) end
        end
        if res.result.finished == false then
          handle_next(token)
        else
          if on_finished then on_finished(all_results) end
        end
      end
    end)
  end

  local id = self.request(method, params, function(response)
    if response.error and on_error then on_error(response) end
    if response.result and response.result.token then
      handle_next(response.result.token)
    else
      vim.print(response)
      error("Response was not an enumerable")
    end
  end)

  return id
end

function M:request_property_enumerate(token, on_yield, on_finished, on_error)
  local all_results = {}

  local function handle_next(enumerable_token)
    self._enumerable_next(enumerable_token, function(res)
      if res.error and on_error then on_error(res) end
      if res.result then
        if #res.result.values > 0 then
          vim.list_extend(all_results, res.result.values)
          if on_yield then on_yield(res.result.values) end
        end
        if res.result.finished == false then
          handle_next(enumerable_token)
        else
          if on_finished then on_finished(all_results) end
        end
      end
    end)
  end

  handle_next(token)
end

---Cancels an active request by ID.
---@param id integer Request ID to cancel
function M.cancel(id)
  if callbacks[id] then
    M.notify("$/cancelRequest", { id = id })
    callbacks[id] = nil
    local on_cancel = cancellation_callbacks[id]
    if on_cancel then on_cancel() end
    cancellation_callbacks[id] = nil
  end
end

function M._enumerable_next(id, cb) M.request("$/enumerator/next", { token = id }, cb) end

---Registers a callback for JSON-RPC notifications.
---@param cb easy-dotnet.RPC.NotificationCallback
---@return fun() unsubscribe Function to remove the callback
function M.subscribe_notifications(cb)
  table.insert(notification_callbacks, cb)

  return function()
    notification_callbacks = vim.tbl_filter(function(fn) return fn ~= cb end, notification_callbacks)
  end
end

---Sends a JSON-RPC notification (no response expected).
---@param method string
---@param params table
---@return boolean success
function M.notify(method, params)
  if not is_connected then error("Client not connected") end

  if not connection then return false end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  local full_message = encode_rpc_message(message)

  local ok, write_result = pcall(vim.loop.write, connection, full_message)

  if not ok or not write_result then return false end

  return true
end

---Disconnects from the server and resets all state.
---@return boolean success
function M.disconnect()
  if connection then
    connection:read_stop()
    connection:close()
    connection = nil
  end

  is_connected = false
  callbacks = {}
  request_id = 0

  return true
end

---Checks if the client is currently connected.
---@return boolean
function M.is_connected() return is_connected and connection ~= nil end

return M
