local extensions = require("easy-dotnet.extensions")
local logger = require("easy-dotnet.logger")

---@class DotnetServer
---@field id integer? Job ID of the running dotnet process
---@field ready boolean Whether the server is ready
---@field is_negotiating boolean Whether the server is starting
---@field callbacks fun()[] List of callbacks to invoke once the pipe is ready
---@field wait any Placeholder for potential future use
---@field pipe_path string? Full resolved pipe path once server is ready
---@field start fun(cb: fun()): nil Starts the dotnet server and invokes `cb` when ready
---@field stop fun(): nil Stops the running dotnet server, if any
---@field get_state fun(): "Running" | "Starting" | "Stopped" gets the state of the dotnet server

---@type DotnetServer
local M = {
  id = nil,
  ready = false,
  callbacks = {},
  wait = nil,
  pipe_path = nil,
  is_negotiating = false,
  ---@diagnostic disable-next-line: assign-type-mismatch
  start = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  stop = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  get_state = nil,
}

function M.start(cb)
  if M.ready then
    cb()
    return
  end

  if M.is_negotiating then
    table.insert(M.callbacks, cb)
    return
  end

  M.is_negotiating = true
  table.insert(M.callbacks, cb)

  local server_ready_prefix = "Named pipe server started: "
  local log_level = require("easy-dotnet.options").get_option("server").log_level

  local args = { "dotnet", "easydotnet" }
  if type(log_level) == "string" then
    table.insert(args, "--logLevel")
    table.insert(args, log_level)
  end

  local handle = vim.fn.jobstart(args, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if not data then return end

      for _, line in ipairs(data) do
        if line:find(server_ready_prefix, 1, true) then
          local pipename = line:sub(#server_ready_prefix + 1)
          local pipe_name = vim.trim(pipename)
          local full_pipe_path
          if extensions.isWindows() then
            -- full_pipe_path = [[\\.\pipe\]] .. pipe_name

            full_pipe_path = [[\\.\pipe\EasyDotnet_ROcrjwn9kiox3tKvRWcQg]]
          elseif extensions.isDarwin() then
            full_pipe_path = os.getenv("TMPDIR") .. "CoreFxPipe_" .. pipe_name
          else
            full_pipe_path = "/tmp/CoreFxPipe_" .. pipe_name
          end

          M.pipe_path = full_pipe_path
          M.ready = true
          M.is_negotiating = false

          for _, callback in ipairs(M.callbacks) do
            pcall(callback)
          end

          M.callbacks = {}
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then logger.warn("[server stderr] " .. line) end
        end
      end
    end,
    on_exit = function(_, code, _)
      vim.notify("dotnet server exited with code " .. code, code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
      M.ready = false
      M.id = nil
      M.is_negotiating = false
      M.callbacks = {}
    end,
  })

  if handle <= 0 then
    M.is_negotiating = false
    error("Failed to start dotnet server")
    return
  end

  M.id = handle
  M.ready = false
end

--- Stops the dotnet server if it's running
function M.stop()
  if M.id and M.ready then
    vim.fn.jobstop(M.id)
    M.ready = false
    M.id = nil
    M.pipe_path = nil
    M.is_negotiating = false
    M.callbacks = {}
    logger.info("Dotnet server stopped.")
  end
end

function M.get_state()
  if M.ready and M.id then
    return "Running"
  elseif M.is_negotiating then
    return "Starting"
  else
    return "Stopped"
  end
end

return M
