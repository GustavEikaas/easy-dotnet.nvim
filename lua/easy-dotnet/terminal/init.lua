---@class easy-dotnet.Terminal.State
---@field buf integer|nil
---@field win integer|nil
---@field header_buf integer|nil
---@field header_win integer|nil
---@field job_id integer|nil
---@field timer any|nil
---@field is_running boolean
---@field last_status string|nil  "running"|"finished"
---@field last_exit_code integer|nil
---@field exec_name string|nil
---@field full_args string|nil

---@type easy-dotnet.Terminal.State
local state = {
  buf = nil,
  win = nil,
  header_buf = nil,
  header_win = nil,
  job_id = nil,
  timer = nil,
  is_running = false,
  last_status = nil,
  last_exit_code = nil,
  exec_name = nil,
  full_args = nil,
}

local M = { state = state }

function M.show()
  local header = require("easy-dotnet.terminal.header")
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    vim.notify("easy-dotnet: no terminal session yet", vim.log.levels.WARN)
    return
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  vim.cmd("split")
  state.win = vim.api.nvim_get_current_win()
  vim.w[state.win].easy_dotnet_terminal = true
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.cmd("normal! G")

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    callback = function()
      state.win = nil
      header.cleanup_header()
    end,
    once = true,
  })

  header.create_header_win()

  if state.last_status then header.update_header(state.last_status, state.last_exit_code) end

  if state.is_running and state.job_id then
    if state.timer then
      state.timer:stop()
      if not state.timer:is_closing() then state.timer:close() end
    end
    local timer = vim.loop.new_timer()
    state.timer = timer
    timer:start(
      0,
      100,
      vim.schedule_wrap(function()
        local codes = vim.fn.jobwait({ state.job_id }, 0)
        if codes[1] == -1 then
          header.update_header("running")
        else
          timer:stop()
          if not timer:is_closing() then timer:close() end
        end
      end)
    )
  end
end

function M.hide()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  vim.api.nvim_win_close(state.win, false)
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.hide()
  else
    M.show()
  end
end

return M
