---@type StreamJsonRpc
local M = {}

---@meta

---@class StreamJsonRpc
---@field setup fun(opts: { pipe_path: string, debug?: boolean }): StreamJsonRpc
---@field connect fun(cb: fun()): nil
---@field connect_sync fun(): nil
---@field request fun(method: DotnetPipeMethod, params: table, callback: fun(result: RPC_Response)): integer|false
---@field notify fun(method: string, params: table): boolean
---@field disconnect fun(): boolean
---@field is_connected fun(): boolean

---@class RPC_Error
---@field code number
---@field message string
---@field data? RPC_Error_Stack

---@class RPC_Error_Stack
---@field type string
---@field message string
---@field stack string
---@field code number

---@class RPC_Response
---@field id number
---@field jsonrpc "2.0"
---@field result? table
---@field error? RPC_Error

---@alias DotnetPipeMethod
---| "initialize"
---| "msbuild/build"
---| "vstest/discover"
---| "vstest/run"
---| "mtp/discover"
---| "mtp/run"

local connection = nil
local is_connected = false
local pipe_path = nil
local request_id = 0
local callbacks = {}
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
  end)
end

function M.connect_sync()
  print("Connecting sync")
  local co = coroutine.running()
  if not co then print("connect sync cannot be called outside of a coroutine") end
  M.connect(function() coroutine.resume(co) end)
  coroutine.yield()
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
