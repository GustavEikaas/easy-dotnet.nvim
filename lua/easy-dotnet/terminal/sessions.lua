--- Tracks terminal buffers whose process runs on the server.
---
--- Neovim owns only the rendering side: `nvim_open_term` gives a terminal instance with no
--- backing process, we push server output into it with `nvim_chan_send`, and forward keystrokes
--- and resize events back over RPC.

---@class easy-dotnet.Terminal.Session
---@field chan integer   -- nvim_open_term channel
---@field buf integer
---@field slot_id string
---@field tab easy-dotnet.TerminalTab|nil -- cleared once detached
---@field rows integer   -- last size reported to the server, so we only resend on a real change
---@field cols integer
---@field detached boolean|nil -- killed; keep the entry so its `terminal/exit` is still consumed

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
---@return integer|nil rows, integer|nil cols
function M.measure(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then return vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_width(win) end
  end
  return nil, nil
end

--- Size to open a terminal at when it has no window yet. Matches the pty defaults on the server.
M.DEFAULT_ROWS = 24
M.DEFAULT_COLS = 80

---@param job_id string
---@param session easy-dotnet.Terminal.Session
function M.register(job_id, session)
  M._by_job[job_id] = session
  M._ensure_autocmds()

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = M._augroup,
    buffer = session.buf,
    once = true,
    callback = function() M.detach(job_id, { keep_tab = true }) end,
  })
end

---@param job_id string
function M.get(job_id) return M._by_job[job_id] end

--- Server output. `data` arrives base64-encoded because pty output is not guaranteed valid UTF-8.
---@param job_id string
---@param data string
function M.write_output(job_id, data)
  local session = M._by_job[job_id]
  if not session or session.detached then return end

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

  M._by_job[job_id] = nil

  local tab = session.tab
  if not tab then return end

  tab.last_status = "finished"
  tab.last_exit_code = exit_code

  local tabline = require("easy-dotnet.terminal.tabline")
  tabline.render()

  local opts = require("easy-dotnet.options").get_option("managed_terminal")
  local manager = require("easy-dotnet.terminal.manager")
  if tab.owned_by == "server" and exit_code == 0 and opts.auto_hide and manager.active_id == session.slot_id then
    local term = require("easy-dotnet.terminal")
    local delay = opts.auto_hide_delay or 0
    if delay > 0 then
      vim.defer_fn(function() term.hide() end, delay)
    else
      term.hide()
    end
  end
end

---@param job_id string
function M.kill(job_id)
  if not M._by_job[job_id] then return end
  notify("terminal/kill", { jobId = job_id })
end

---@param job_id string
---@param opts? { keep_tab?: boolean }
function M.detach(job_id, opts)
  local session = M._by_job[job_id]
  if not session or session.detached then return end

  M.kill(job_id)
  session.detached = true
  if not (opts and opts.keep_tab) then session.tab = nil end
end

---@param slot_id string
function M.close_by_slot(slot_id)
  for job_id, session in pairs(M._by_job) do
    if session.slot_id == slot_id then M.detach(job_id) end
  end
end

function M.close_all()
  for job_id, _ in pairs(M._by_job) do
    M.detach(job_id)
  end
end

function M.sync_sizes()
  for job_id, session in pairs(M._by_job) do
    if not session.detached and vim.api.nvim_buf_is_valid(session.buf) then
      local rows, cols = M.measure(session.buf)
      if rows and (rows ~= session.rows or cols ~= session.cols) then
        session.rows, session.cols = rows, cols
        notify("terminal/resize", { jobId = job_id, cols = cols, rows = rows })
      end
    end
  end
end

--- Dragging a split emits a burst of WinResized; coalesce them into one notification per settle.
local resize_timer = nil

local function schedule_sync()
  if not resize_timer then resize_timer = vim.uv.new_timer() end
  resize_timer:stop()
  resize_timer:start(50, 0, vim.schedule_wrap(function() M.sync_sizes() end))
end

function M._ensure_autocmds()
  if M._augroup then return end

  M._augroup = vim.api.nvim_create_augroup("EasyDotnetTerminalSessions", { clear = true })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "BufWinEnter", "WinClosed" }, {
    group = M._augroup,
    callback = schedule_sync,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = M._augroup,
    callback = function() M.close_all() end,
  })
end

return M
