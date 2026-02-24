local logger = require("easy-dotnet.logger")

---@class easy-dotnet.Server.Server
---@field id integer? Job ID of the running dotnet process
---@field ready boolean Whether the server is ready
---@field is_negotiating boolean Whether the server is starting
---@field callbacks fun()[] List of callbacks to invoke once the pipe is ready
---@field wait any Placeholder for potential future use
---@field pipe_path string? Full resolved pipe path once server is ready
---@field start fun(cb: fun()): nil Starts the dotnet server and invokes `cb` when ready
---@field stop fun(): nil Stops the running dotnet server, if any
---@field get_state fun(): "Running" | "Starting" | "Stopped" gets the state of the dotnet server
---@field log_history string[] Stores the stdout/stderr of the server
---@field dump_logs fun(): nil Dumps the captured logs into a new scratch buffer

---@type easy-dotnet.Server.Server
local M = {
  id = nil,
  ready = false,
  callbacks = {},
  wait = nil,
  pipe_path = nil,
  is_negotiating = false,
  log_history = {},
  log_buf_nr = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  start = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  stop = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  get_state = nil,
  ---@diagnostic disable-next-line: assign-type-mismatch
  dump_logs = nil,
}

local function append_log(prefix, line)
  if line and line ~= "" then
    local formatted_line = prefix .. line
    table.insert(M.log_history, formatted_line)
    -- Cap the log history to the last 5000 lines
    if #M.log_history > 5000 then table.remove(M.log_history, 1) end

    if M.log_buf_nr and vim.api.nvim_buf_is_valid(M.log_buf_nr) then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(M.log_buf_nr) then
          vim.bo[M.log_buf_nr].modifiable = true
          vim.api.nvim_buf_set_lines(M.log_buf_nr, -1, -1, false, { formatted_line })
          vim.bo[M.log_buf_nr].modifiable = false
        end
      end)
    end
  end
end

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
  M.log_history = {}
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
        append_log("[STDOUT] ", line)
        if line:find(server_ready_prefix, 1, true) then
          local pipe_name = vim.trim(line:sub(#server_ready_prefix + 1))

          M.pipe_path = require("easy-dotnet.rpc.rpc").get_pipe_path(pipe_name)
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
          if line ~= "" then
            append_log("[STDERR] ", line)
            logger.warn("[server stderr] " .. line)
          end
        end
      end
    end,
    on_exit = function(_, code, _)
      append_log("[SYSTEM] ", "Process exited with code " .. tostring(code))
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

function M.dump_logs()
  if #M.log_history == 0 then
    vim.notify("No logs captured for dotnet server yet.", vim.log.levels.WARN)
    return
  end

  if M.log_buf_nr and vim.api.nvim_buf_is_valid(M.log_buf_nr) then
    vim.notify("Log buffer is already open!", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  M.log_buf_nr = buf
  vim.api.nvim_buf_set_name(buf, "DotnetServerLogs_" .. tostring(os.time()))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.log_history)
  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "log"
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  vim.cmd("normal! G")
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
