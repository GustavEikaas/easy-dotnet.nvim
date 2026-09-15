--- Tracks terminal buffers whose process runs on the server.
---
--- Neovim owns only the rendering side: `nvim_open_term` gives a terminal instance with no
--- backing process, we push server output into it with `nvim_chan_send`, and forward keystrokes
--- and resize events back over RPC.

---@class easy-dotnet.Terminal.Session
---@field chan integer   -- nvim_open_term channel
---@field buf integer
---@field slot_id string
---@field tab easy-dotnet.TerminalTab

local M = {
  ---@type table<string, easy-dotnet.Terminal.Session>
  _by_job = {},
}

local function notify(method, params)
  local rpc = require("easy-dotnet.rpc.rpc")
  local client = rpc.global_rpc_client
  if client and client._initialized then pcall(function() client._client.notify(method, params) end) end
end

---@param buf integer
---@return integer rows, integer cols
function M.measure(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
      return vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_width(win)
    end
  end
  return 24, 80
end

---@param job_id string
---@param session easy-dotnet.Terminal.Session
function M.register(job_id, session)
  M._by_job[job_id] = session
  M._ensure_resize_autocmd()
end

---@param job_id string
function M.get(job_id) return M._by_job[job_id] end

--- Server output. `data` arrives base64-encoded because pty output is not guaranteed valid UTF-8.
---@param job_id string
---@param data string
function M.write_output(job_id, data)
  local session = M._by_job[job_id]
  if not session then return end

  local ok, decoded = pcall(vim.base64.decode, data)
  if not ok then return end

  pcall(vim.api.nvim_chan_send, session.chan, decoded)
end

--- Keystrokes from the terminal buffer, already encoded as terminal bytes by Neovim.
---@param job_id string
---@param data string
function M.send_input(job_id, data) notify("terminal/input", { jobId = job_id, data = vim.base64.encode(data) }) end

---@param job_id string
---@param exit_code integer
function M.on_exit(job_id, exit_code)
  local session = M._by_job[job_id]
  if not session then return end

  session.tab.last_status = "finished"
  session.tab.last_exit_code = exit_code
  M._by_job[job_id] = nil

  local tabline = require("easy-dotnet.terminal.tabline")
  tabline.render()

  local opts = require("easy-dotnet.options").get_option("managed_terminal")
  local manager = require("easy-dotnet.terminal.manager")
  if session.tab.owned_by == "server" and exit_code == 0 and opts.auto_hide and manager.active_id == session.slot_id then
    local term = require("easy-dotnet.terminal")
    local delay = opts.auto_hide_delay or 0
    if delay > 0 then
      vim.defer_fn(function() term.hide() end, delay)
    else
      term.hide()
    end
  end
end

---@param slot_id string
function M.close_by_slot(slot_id)
  for job_id, session in pairs(M._by_job) do
    if session.slot_id == slot_id then M._by_job[job_id] = nil end
  end
end

--- Tell the server when the rendering window changes size, so the pty's winsize matches and
--- programs relying on COLUMNS/LINES wrap correctly.
function M._ensure_resize_autocmd()
  if M._resize_autocmd then return end

  M._resize_autocmd = vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = vim.api.nvim_create_augroup("EasyDotnetTerminalResize", { clear = true }),
    callback = function()
      for job_id, session in pairs(M._by_job) do
        if vim.api.nvim_buf_is_valid(session.buf) then
          local rows, cols = M.measure(session.buf)
          notify("terminal/resize", { jobId = job_id, cols = cols, rows = rows })
        end
      end
    end,
  })
end

return M
