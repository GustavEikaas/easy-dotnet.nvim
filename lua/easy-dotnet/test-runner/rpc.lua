---@alias DotnetPipeMethod
---| "VSTest_Discover"
---| "VSTest_Run"
---| "MTP_Discover"
---| "MTP_Run"

---@class DotnetPipe
---@field send fun(method: DotnetPipeMethod, params: table, callback: fun(response: table)): nil
---@field close fun(): nil

---Creates a new DotnetPipe instance.
---@return DotnetPipe
local function new()
  local self = {}

  local client = nil
  local connected = false
  local callbacks = {}
  local _id = 0

  local function get_pipe_path()
    return "\\\\.\\pipe\\EasyDotnetPipe"
  end

  local function get_command_id()
    _id = _id + 1
    return _id
  end

  local function read_loop()
    client:read_start(function(err, data)
      if err then
        vim.schedule(function()
          vim.notify("Pipe read error: " .. err, vim.log.levels.ERROR)
        end)
        return
      end

      if data then
        for line in data:gmatch("[^\r\n]+") do
          local ok, decoded = pcall(vim.json.decode, line)
          if ok and decoded and decoded.id then
            local cb = callbacks[decoded.id]
            if cb then
              callbacks[decoded.id] = nil
              vim.schedule(function()
                cb(decoded)
              end)
            end
          else
            vim.schedule(function()
              vim.notify("Malformed or unmatched response: " .. line, vim.log.levels.WARN)
            end)
          end
        end
      end
    end)
  end

  local function connect_pipe(callback)
    if connected and client and not client:is_closing() then
      callback()
      return
    end

    client = vim.loop.new_pipe(false)
    client:connect(get_pipe_path(), function(err)
      if err then
        vim.schedule(function()
          vim.notify("Failed to connect: " .. err, vim.log.levels.ERROR)
        end)
        return
      end
      connected = true
      read_loop()
      callback()
    end)
  end

  function self.send(method, params, callback)
    connect_pipe(function()
      local id = get_command_id()
      local message = {
        id = id,
        method = method,
        params = params or {},
      }
      vim.schedule(function()
        vim.print("Sending message", message)
      end)
      callbacks[id] = callback
      client:write(vim.json.encode(message) .. "\n")
    end)
  end

  function self.close()
    if client and not client:is_closing() then
      client:shutdown(function()
        client:close()
        client = nil
        connected = false
      end)
    end
  end

  return self
end

return new
