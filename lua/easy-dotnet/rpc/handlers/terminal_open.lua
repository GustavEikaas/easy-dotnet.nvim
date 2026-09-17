local sessions = require("easy-dotnet.terminal.sessions")

---@class easy-dotnet.Server.TerminalOpenRequest
---@field jobId string
---@field slotId string|nil
---@field label string
---@field arguments string[]|nil

--- Allocates a terminal buffer for a process that runs on the *server*. Neovim never spawns
--- anything here: output arrives as `terminal/output` notifications and keystrokes are forwarded
--- back as `terminal/input`.
---@param params easy-dotnet.Server.TerminalOpenRequest
return function(params, response, throw, validate)
  local ok, err = validate({ jobId = "string" }, params)
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local manager = require("easy-dotnet.terminal.manager")
  local tabline = require("easy-dotnet.terminal.tabline")
  local term = require("easy-dotnet.terminal")

  local slot_id = params.slotId or "default"
  local label = slot_id == "default" and params.label or slot_id:match("^run:(.+)$") or slot_id
  local tab = manager.get_or_create(slot_id, label, "server")

  sessions.close_by_slot(slot_id)

  local old_buf = tab.buf
  tab.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tab.buf].bufhidden = "hide"
  vim.bo[tab.buf].buflisted = false

  tab.exec_name = params.label
  tab.full_args = table.concat(params.arguments or {}, " ")
  tab.last_status = "running"
  tab.last_exit_code = nil
  tab.owned_by = "server"

  manager.set_active(slot_id)
  term.show()

  local job_id = params.jobId
  local chan = vim.api.nvim_open_term(tab.buf, {
    on_input = function(_, _, _, data) sessions.send_input(job_id, data) end,
  })

  local rows, cols = sessions.measure(tab.buf)
  rows = rows or sessions.DEFAULT_ROWS
  cols = cols or sessions.DEFAULT_COLS

  sessions.register(job_id, { chan = chan, buf = tab.buf, slot_id = slot_id, tab = tab, rows = rows, cols = cols })

  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then pcall(vim.api.nvim_buf_delete, old_buf, { force = true }) end

  tabline.ensure_timer()

  if vim.api.nvim_get_current_buf() == tab.buf then vim.cmd("startinsert") end

  response({ rows = rows, cols = cols })
end
