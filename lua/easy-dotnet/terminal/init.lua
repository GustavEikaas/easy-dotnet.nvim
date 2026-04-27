local manager = require("easy-dotnet.terminal.manager")
local Tab = require("easy-dotnet.terminal.tab")

local M = {}

local panel_height = 15

local function apply_panel_keymaps(buf)
  local km = require("easy-dotnet.options").get_option("managed_terminal").mappings or {}
  local opts = { nowait = true, silent = true, buffer = buf }

  vim.keymap.set("n", km.next_tab and km.next_tab.lhs or "<Tab>", function()
    local tabs = manager.get_all()
    for i, tab in ipairs(tabs) do
      if tab.id == manager.active_id then
        local next = tabs[i + 1] or tabs[1]
        manager.set_active(next.id)
        return
      end
    end
  end, vim.tbl_extend("force", opts, { desc = km.next_tab and km.next_tab.desc or "Next terminal tab" }))

  vim.keymap.set("n", km.prev_tab and km.prev_tab.lhs or "<S-Tab>", function()
    local tabs = manager.get_all()
    for i, tab in ipairs(tabs) do
      if tab.id == manager.active_id then
        local prev = tabs[i - 1] or tabs[#tabs]
        manager.set_active(prev.id)
        return
      end
    end
  end, vim.tbl_extend("force", opts, { desc = km.prev_tab and km.prev_tab.desc or "Previous terminal tab" }))

  vim.keymap.set("n", km.new_terminal and km.new_terminal.lhs or "+", function()
    local new_tab = manager.new_user_terminal()
    manager.set_active(new_tab.id)
    require("easy-dotnet.terminal.tabline").ensure_timer()
  end, vim.tbl_extend("force", opts, { desc = km.new_terminal and km.new_terminal.desc or "New user terminal" }))

  vim.keymap.set("n", km.close_terminal and km.close_terminal.lhs or "X", function()
    if manager.active_id then manager.remove(manager.active_id) end
  end, vim.tbl_extend("force", opts, { desc = km.close_terminal and km.close_terminal.desc or "Close terminal tab" }))

  vim.keymap.set("n", km.hide_panel and km.hide_panel.lhs or "q", function() M.hide() end, vim.tbl_extend("force", opts, { desc = km.hide_panel and km.hide_panel.desc or "Hide terminal panel" }))
end

local function setup_panel_window(win)
  manager.panel_win = win
  vim.w[win].easy_dotnet_terminal = true

  manager._on_tab_activated = function(tab) apply_panel_keymaps(tab.buf) end
end

function M.show()
  if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then
    vim.api.nvim_set_current_win(manager.panel_win)
    return
  end

  if #manager.get_all() == 0 then
    local tab = manager.new_user_terminal()
    manager.active_id = tab.id
  end

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_height(win, panel_height)

  local active = manager.active_id and manager.get(manager.active_id)
  if active then
    Tab.ensure_buf(active)
    vim.api.nvim_win_set_buf(win, active.buf)
    vim.cmd("normal! G")
  end

  setup_panel_window(win)

  if active then apply_panel_keymaps(active.buf) end

  require("easy-dotnet.terminal.tabline").create(win)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then panel_height = vim.api.nvim_win_get_height(manager.panel_win) end
      manager.panel_win = nil
      require("easy-dotnet.terminal.tabline").destroy()
    end,
  })
end

function M.hide()
  if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then vim.api.nvim_win_close(manager.panel_win, false) end
end

function M.toggle()
  if manager.panel_win and vim.api.nvim_win_is_valid(manager.panel_win) then
    M.hide()
  else
    M.show()
  end
end

---Switch the active tab to the given slot id, showing the panel if needed.
---@param slot_id string
function M.switch(slot_id)
  manager.set_active(slot_id)
  M.show()
end

function M.new_user_terminal()
  local tab = manager.new_user_terminal()
  manager.set_active(tab.id)
  M.show()
  require("easy-dotnet.terminal.tabline").ensure_timer()
end

return M
