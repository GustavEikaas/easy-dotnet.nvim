local Tree = require("easy-dotnet.test-runnerv2.v2")

local M = {
  buf = nil,
  win = nil,
  keymap = require("easy-dotnet.test-runnerv2.keymaps")(),
  ns_id = vim.api.nvim_create_namespace("EasyDotnetTree"),
}

-- Recursive render helper
local function render_node(node, indent, lines)
  local prefix = string.rep("  ", indent)
  local status = Tree.get_status(node.id) or ""
  table.insert(lines, prefix .. node.displayName .. (status ~= "" and (" [" .. status .. "]") or ""))

  -- Only render children if node is expanded
  if not node.expanded then return end

  local keys = vim.tbl_keys(node.children or {})
  table.sort(keys, function(a, b) return node.children[a].displayName < node.children[b].displayName end)
  for _, key in ipairs(keys) do
    render_node(node.children[key], indent + 1, lines)
  end
end

local function apply_keymaps()
  if not M.keymap or not M.buf then return end
  for key, map in pairs(M.keymap) do
    vim.keymap.set("n", key, function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local node = Tree.get_root()
      if not node then return end
      -- Find node by line index
      local current_line = 1
      local target = nil
      local function traverse(n)
        if target then return end
        if current_line == line then target = n end
        current_line = current_line + 1
        if n.expanded then
          for _, child in pairs(n.children or {}) do
            traverse(child)
          end
        end
      end
      traverse(node)
      if target and map.handle then map.handle(target, M) end
    end, { buffer = M.buf, desc = map.desc, noremap = true, silent = true })
  end
end

-- Render tree to buffer
function M.render()
  local root = Tree.get_root()
  if not root then
    vim.notify("[TreeView] No root node to render", vim.log.levels.WARN)
    return
  end

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
    M.buf = vim.api.nvim_create_buf(false, true) -- scratch, unlisted
  end

  if not M.win or not vim.api.nvim_win_is_valid(M.win) then
    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local opts = {
      relative = "editor",
      width = width,
      height = height,
      col = math.floor((vim.o.columns - width) / 2),
      row = math.floor((vim.o.lines - height) / 2),
      style = "minimal",
      border = "rounded",
    }
    M.win = vim.api.nvim_open_win(M.buf, true, opts)
    vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
  end

  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local lines = {}
  render_node(root, 0, lines)
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", false)

  apply_keymaps()
end

-- Show the floating tree
function M.show()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_set_current_win(M.win)
    return
  end
  M.render()
end

-- Hide the floating tree
function M.hide()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
end

-- Toggle the floating tree visibility
function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    M.hide()
  else
    M.show()
  end
end

function M.set_keymaps(maps) end
-- M.keymap = maps
return M
