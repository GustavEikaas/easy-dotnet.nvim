-- StreamJsonRpc client for Neovim
-- Implements a singleton pattern for IPC with C# server

local M = {}

-- Private module variables
local connection = nil
local is_connected = false
local pipe_path = nil
local request_id = 0
local callbacks = {}
local event_handlers = {}
local reconnect_timer = nil
local heartbeat_timer = nil
local debug_mode = false

-- Helper function to log debug messages
local function debug_log(msg)
  if debug_mode then vim.notify("StreamJsonRpc Debug: " .. msg, vim.log.levels.DEBUG) end
end

-- Helper function to check if the pipe exists (Windows-specific approach)
local function pipe_exists(path)
  -- On Windows, we can't easily check if a named pipe exists through normal file operations
  -- so we'll just assume it exists and try to connect
  return true
end

-- Initialize the client with the pipe path
function M.setup(opts)
  opts = opts or {}
  pipe_path = opts.pipe_path
  debug_mode = opts.debug or false

  if not pipe_path then error("StreamJsonRpc client: pipe_path is required") end

  -- Make sure we clean up connections on exit
  vim.api.nvim_create_autocmd("VimLeave", {
    callback = function() M.disconnect() end,
  })

  -- Try to connect immediately if auto_connect is set
  if opts.auto_connect then vim.defer_fn(function() M.connect() end, 100) end

  debug_log("Setup complete with pipe_path: " .. pipe_path)
  return M
end

-- Connect to the server if not already connected
function M.connect()
  -- Don't try to connect if we're already connected
  if is_connected and connection then
    debug_log("Already connected, skipping connection attempt")
    return true
  end

  -- Clear any existing timers
  if reconnect_timer then
    vim.loop.timer_stop(reconnect_timer)
    reconnect_timer = nil
  end

  if heartbeat_timer then
    vim.loop.timer_stop(heartbeat_timer)
    heartbeat_timer = nil
  end

  if not pipe_path then error("StreamJsonRpc client: setup() must be called before connect()") end

  debug_log("Attempting to connect to pipe: " .. pipe_path)

  -- Try to open the pipe
  local pipe = vim.loop.new_pipe(false)

  if not pipe then
    vim.notify("StreamJsonRpc client: failed to create pipe", vim.log.levels.ERROR)
    return false
  end

  -- Store connection early to ensure singleton
  connection = pipe

  local connect_result, connect_error = vim.loop.pipe_connect(pipe, pipe_path)

  if not connect_result then
    vim.notify("StreamJsonRpc client: connection failed - " .. (connect_error or "unknown error"), vim.log.levels.ERROR)
    pipe:close()
    connection = nil

    -- Schedule reconnect attempt
    reconnect_timer = vim.defer_fn(function()
      debug_log("Attempting to reconnect...")
      M.connect()
    end, 2000)

    return false
  end

  -- Set up reading from the pipe
  local buffer = ""

  vim.loop.read_start(pipe, function(err, data)
    print("We recieved some data")
    if err then
      vim.schedule(function()
        vim.notify("StreamJsonRpc client: read error - " .. err, vim.log.levels.ERROR)
        M.disconnect()
      end)
      return
    end

    if data then
      debug_log("Received data: " .. #data .. " bytes")
      buffer = buffer .. data

      -- Process complete JSON messages
      while true do
        local start, finish, message = M._find_json_message(buffer)

        if not start then break end

        -- Remove the processed message from buffer
        buffer = string.sub(buffer, finish + 1)

        -- Process the message in the main Neovim thread
        vim.schedule(function() M._handle_message(message) end)
      end
    else
      -- EOF received
      vim.schedule(function()
        vim.notify("StreamJsonRpc client: server closed the connection", vim.log.levels.INFO)
        M.disconnect()

        -- Schedule reconnect attempt
        reconnect_timer = vim.defer_fn(function()
          debug_log("Attempting to reconnect after EOF...")
          M.connect()
        end, 2000)
      end)
    end
  end)

  -- Mark as connected
  is_connected = true

  -- Send initial handshake
  -- Send an empty notification to keep the connection alive
  M.notify("handshake", { client = "neovim_streamjsonrpc_client" })

  -- Set up heartbeat timer to keep connection alive
  heartbeat_timer = vim.loop.new_timer()
  heartbeat_timer:start(
    5000,
    5000,
    vim.schedule_wrap(function()
      if is_connected then
        -- debug_log("Sending heartbeat")
        -- M.notify("heartbeat", { timestamp = os.time() })
      end
    end)
  )

  vim.notify("StreamJsonRpc client: connected to server", vim.log.levels.INFO)
  debug_log("Connection established successfully")

  return true
end

-- Find a complete JSON message in a buffer
function M._find_json_message(buffer)
  local start_pos = 1
  local header_end = string.find(buffer, "\r\n\r\n", start_pos)

  if not header_end then return nil end

  local headers = string.sub(buffer, start_pos, header_end - 1)
  local content_length_match = string.match(headers, "Content%-Length: (%d+)")

  if not content_length_match then
    debug_log("No Content-Length header found")
    return nil
  end

  local content_length = tonumber(content_length_match)
  local body_start = header_end + 4
  local body_end = body_start + content_length - 1

  if #buffer < body_end then
    debug_log("Buffer too short, waiting for more data")
    return nil
  end

  local body = string.sub(buffer, body_start, body_end)
  local success, message = pcall(vim.json.decode, body)

  if not success then
    vim.notify("StreamJsonRpc client: JSON decode error - " .. message, vim.log.levels.ERROR)
    debug_log("Failed JSON: " .. body)
    return body_start, body_end, nil
  end

  debug_log("Decoded message: " .. vim.inspect(message))
  return body_start, body_end, message
end

-- Handle incoming message
function M._handle_message(message)
  if not message then
    debug_log("Received nil message")
    return
  end

  -- Handle response
  if message.id and callbacks[message.id] then
    debug_log("Handling response for request ID: " .. message.id)
    local callback = callbacks[message.id]
    callbacks[message.id] = nil

    if message.error then
      callback(nil, message.error)
    else
      callback(message.result, nil)
    end
    return
  end

  -- Handle notification/event
  if message.method and not message.id then
    debug_log("Handling notification: " .. message.method)
    local event_handler = event_handlers[message.method]
    if event_handler then
      event_handler(message.params)
    else
      debug_log("No handler registered for method: " .. message.method)
    end
  end
end

-- Send request to server
function M.request(method, params, callback)
  if not is_connected then
    debug_log("Not connected, attempting to connect...")
    if not M.connect() then
      if callback then vim.schedule(function() callback(nil, "Not connected to server") end) end
      return false
    end
  end

  request_id = request_id + 1
  local id = request_id

  local message = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  if callback then callbacks[id] = callback end

  local json_message = vim.json.encode(message)
  local header = string.format("Content-Length: %d\r\n\r\n", #json_message)
  local full_message = header .. json_message

  debug_log("Sending request: " .. method .. " (ID: " .. id .. ")")
  vim.loop.write(connection, full_message)

  return true
end

-- Send notification to server (no response expected)
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

  debug_log("Sending notification: " .. method)
  local write_result, write_error = vim.loop.write(connection, full_message)

  if not write_result then
    debug_log("Write failed: " .. (write_error or "unknown error"))
    return false
  end

  return true
end

-- Register event handler for server notifications
function M.on_notification(method, callback)
  debug_log("Registering handler for: " .. method)
  event_handlers[method] = callback
end

-- Disconnect from server
function M.disconnect()
  debug_log("Disconnecting...")

  -- Stop timers
  if reconnect_timer then
    vim.loop.timer_stop(reconnect_timer)
    reconnect_timer = nil
  end

  if heartbeat_timer then
    vim.loop.timer_stop(heartbeat_timer)
    heartbeat_timer = nil
  end

  -- Clean up connection
  if connection then
    -- Try to send a goodbye notification
    if is_connected then pcall(function() M.notify("goodbye", { reason = "client_disconnect" }) end) end

    vim.loop.read_stop(connection)
    connection:close()
    connection = nil
  end

  is_connected = false
  callbacks = {}
  request_id = 0

  debug_log("Disconnected successfully")
  return true
end

-- Check if connected
function M.is_connected() return is_connected and connection ~= nil end

-- Enable or disable debug logging
function M.set_debug(enable)
  debug_mode = enable
  return M
end

-- Expose version and metadata
M.version = "1.0.0"
M.description = "StreamJsonRpc client for Neovim with singleton pattern"

return M
