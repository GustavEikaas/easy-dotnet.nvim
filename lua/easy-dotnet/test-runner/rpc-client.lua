---@type StreamJsonRpc
local M = {}

---@meta

---@class StreamJsonRpc
---@field setup fun(opts: { pipe_path: string, debug?: boolean }): StreamJsonRpc
---@field connect fun(cb: fun()): nil
---@field connect_sync fun(): nil
---@field request fun(method: DotnetPipeMethod, params: table, callback: fun(result: any?, error: any?)): integer|false
---@field notify fun(method: string, params: table): boolean
---@field disconnect fun(): boolean
---@field is_connected fun(): boolean
---@field on_server_request fun(method: string, callback: fun(params: table): any): StreamJsonRpc
---@field on_server_notification fun(method: string, callback: fun(params: table)): StreamJsonRpc
---@field _find_json_message fun(buffer: string): (integer?, integer?, table?)
---@field _handle_message fun(message: table): nil

---@alias DotnetPipeMethod
---| "vstest/discover"
---| "vstest/run"
---| "mtp/discover"
---| "mtp/run"

local connection = nil
local is_connected = false
local pipe_path = nil
local request_id = 0
local callbacks = {}
local event_handlers = {}
local debug_mode = false

local function debug_log(msg)
  if debug_mode then vim.notify("StreamJsonRpc Debug: " .. msg, vim.log.levels.DEBUG) end
end

function M.setup(opts)
  opts = opts or {}
  pipe_path = opts.pipe_path
  debug_mode = opts.debug or false

  if not pipe_path then error("StreamJsonRpc client: pipe_path is required") end

  debug_log("Setup complete with pipe_path: " .. pipe_path)
  return M
end

local function read_loop()
  connection:read_start(function(err, data)
    if err then
      vim.schedule(function() vim.notify("Pipe read error: " .. err, vim.log.levels.ERROR) end)
      return
    end

    if not data then return end

    local header_end = data:find("\r\n\r\n", 1, true)
    if not header_end then
      vim.schedule(function() vim.notify("Incomplete JSON-RPC header", vim.log.levels.WARN) end)
      return
    end

    local header_section = data:sub(1, header_end - 1)
    local content_length = header_section:match("Content%-Length:%s*(%d+)")
    if not content_length then
      vim.schedule(function() vim.notify("Missing Content-Length header", vim.log.levels.WARN) end)
      return
    end

    content_length = tonumber(content_length)
    local body_start = header_end + 4
    local body = data:sub(body_start, body_start + content_length - 1)

    local ok, decoded = pcall(vim.json.decode, body)
    if ok and decoded and decoded.id then
      local cb = callbacks[decoded.id]
      if cb then
        callbacks[decoded.id] = nil
        vim.schedule(function() cb(decoded) end)
      end
    else
      vim.schedule(function() vim.notify("Malformed or unmatched JSON body: " .. body, vim.log.levels.WARN) end)
    end
  end)
end

function M.connect(cb)
  if is_connected and connection then
    debug_log("Already connected, skipping connection attempt")
    cb()
  end
  if not pipe_path then error("StreamJsonRpc client: setup() must be called before connect()") end

  debug_log("Attempting to connect to pipe: " .. pipe_path)

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
    -- vim.notify("StreamJsonRpc client: connected to server", vim.log.levels.INFO)
    -- debug_log("Connection established successfully")
  end)
end

function M.connect_sync()
  print("Connecting sync")
  local co = coroutine.running()
  if not co then print("connect sync cannot be called outside of a coroutine") end
  M.connect(function() coroutine.resume(co) end)
  coroutine.yield()
end

function M._find_json_message(buffer)
  local start_pos = 1
  local header_end = string.find(buffer, "\r\n\r\n", start_pos)

  if not header_end then
    debug_log("No header end found in buffer of length " .. #buffer)
    return nil
  end

  local headers = string.sub(buffer, start_pos, header_end - 1)
  local content_length_match = string.match(headers, "Content%-Length: (%d+)")

  if not content_length_match then
    debug_log("No Content-Length header found in: " .. headers)
    return nil
  end

  local content_length = tonumber(content_length_match)
  local body_start = header_end + 4
  local body_end = body_start + content_length - 1

  if #buffer < body_end then
    debug_log("Buffer too short (" .. #buffer .. " bytes), waiting for more data. Need " .. body_end .. " bytes")
    return nil
  end

  local body = string.sub(buffer, body_start, body_end)
  debug_log("Attempting to decode JSON body: " .. body)

  local success, message = pcall(vim.json.decode, body)

  if not success then
    vim.notify("StreamJsonRpc client: JSON decode error - " .. message, vim.log.levels.ERROR)
    debug_log("Failed JSON: " .. body)
    return body_start, body_end, nil
  end

  debug_log("Successfully decoded message: " .. vim.inspect(message))
  return body_start, body_end, message
end

function M._handle_message(message)
  if not message then
    debug_log("Received nil message")
    return
  end

  debug_log("Processing message: " .. vim.inspect(message))

  if message.id and (message.result ~= nil or message.error ~= nil) then
    debug_log("Handling response for request ID: " .. message.id)
    local callback = callbacks[message.id]

    if callback then
      callbacks[message.id] = nil

      if message.error then
        debug_log("Error in response: " .. vim.inspect(message.error))
        callback(nil, message.error)
      else
        debug_log("Result in response: " .. vim.inspect(message.result))
        callback(message.result, nil)
      end
    end
    return
  end

  if message.method and message.id == nil then
    debug_log("Handling notification: " .. message.method)
    local event_handler = event_handlers[message.method]
    if event_handler then event_handler(message.params) end
    return
  end

  if message.method and message.id then
    local request_handler = event_handlers[message.method]

    if request_handler then
      local result, error

      local success, handler_result = pcall(function() return request_handler(message.params) end)

      if success then
        result = handler_result
      else
        error = {
          code = -32603,
          message = "Error processing request: " .. tostring(handler_result),
        }
      end

      local response = {
        jsonrpc = "2.0",
        id = message.id,
      }

      if error then
        response.error = error
      else
        response.result = result
      end

      local json_response = vim.json.encode(response)
      local header = string.format("Content-Length: %d\r\n\r\n", #json_response)
      local full_response = header .. json_response

      debug_log("Sending response: " .. vim.inspect(response))
      connection:write(full_response)
    else
      debug_log("No handler for server request: " .. message.method)
      local response = {
        jsonrpc = "2.0",
        id = message.id,
        error = {
          code = -32601,
          message = "Method not found",
        },
      }

      local json_response = vim.json.encode(response)
      local header = string.format("Content-Length: %d\r\n\r\n", #json_response)
      local full_response = header .. json_response

      connection:write(full_response)
    end
    return
  end

  debug_log("Unhandled message type: " .. vim.inspect(message))
end

function M.request(method, params, callback)
  --nil check, method, params, callback
  if not is_connected then M.connect_sync() end

  request_id = request_id + 1
  local id = request_id

  local message = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  debug_log("Registering callback for request ID: " .. id)

  callbacks[id] = callback

  local json_message = vim.json.encode(message)
  local header = string.format("Content-Length: %d\r\n\r\n", #json_message)
  local full_message = header .. json_message

  debug_log("Sending request: " .. method .. " (ID: " .. id .. "), content: " .. json_message)

  local ok, write_result = pcall(vim.loop.write, connection, full_message)

  if not ok or not write_result then
    debug_log("Write failed: " .. (not ok and write_result or "unknown error"))
    callbacks[id] = nil
    if callback then vim.schedule(function() callback(nil, "Failed to send request") end) end
    return false
  end

  return id
end

function M.notify(method, params)
  if not is_connected then
    debug_log("Not connected for notification, attempting to connect...")
    if not M.connect() then return false end
  end

  if not connection then
    debug_log("Connection object is nil, cannot send notification")
    return false
  end

  local message = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }

  local json_message = vim.json.encode(message)
  local header = string.format("Content-Length: %d\r\n\r\n", #json_message)
  local full_message = header .. json_message

  debug_log("Sending notification: " .. method .. ", content: " .. json_message)

  local ok, write_result = pcall(vim.loop.write, connection, full_message)

  if not ok or not write_result then
    debug_log("Write failed: " .. (not ok and write_result or "unknown error"))
    return false
  end

  return true
end

function M.on_server_request(method, callback)
  event_handlers[method] = callback
  return M
end

function M.on_server_notification(method, callback)
  debug_log("Registering handler for: " .. method)
  event_handlers[method] = callback
  return M
end

function M.disconnect()
  debug_log("Disconnecting...")

  if connection then
    connection:read_stop()
    connection:close()
    connection = nil
  end

  is_connected = false
  callbacks = {}
  request_id = 0

  debug_log("Disconnected successfully")
  return true
end

function M.is_connected() return is_connected and connection ~= nil end

return M
