local M = {}

-- === CONFIG ===
local AXIS_COL_WIDTH = 12 -- Screen columns reserved for the Y-Axis labels

-- === UTILITIES ===

local function format_bytes(b)
  if b < 1024 then return string.format("%d B", b) end
  local kb = b / 1024
  if kb < 1024 then return string.format("%.1f KB", kb) end
  local mb = kb / 1024
  if mb < 1024 then return string.format("%.1f MB", mb) end
  local gb = mb / 1024
  return string.format("%.1f GB", gb)
end

local function format_percent(v) return string.format("%d%%", math.floor(v)) end

local braille_map = { { 0x1, 0x8 }, { 0x2, 0x10 }, { 0x4, 0x20 }, { 0x40, 0x80 } }

local function pad_label(text, separator)
  -- Content Width = Text Length + 1 space + 1 char for separator
  local content_width = #text + 1 + 1
  local padding = AXIS_COL_WIDTH - content_width
  if padding < 0 then padding = 0 end
  return string.rep(" ", padding) .. text .. " " .. separator
end

-- === GRAPH CLASS ===

local Graph = {}
Graph.__index = Graph

function Graph.new(opts)
  local self = setmetatable({}, Graph)
  self.type = opts.type or "percent"
  self.title_fmt = opts.title or " Graph (%s) "
  self.color = opts.color or "CpuNormal"
  self.width = opts.width or 60
  self.height = opts.height or 12

  self.buf = -1
  self.win = -1
  self.data = {}
  self.max_points = self.width * 2

  for _ = 1, self.max_points do
    table.insert(self.data, 0)
  end

  self.last_render = 0
  self.throttle_ms = 33
  return self
end

function Graph:get_max_y()
  if self.type == "percent" then return 100 end
  local max_val = 1
  for _, v in ipairs(self.data) do
    if v > max_val then max_val = v end
  end
  return max_val * 1.1
end

function Graph:render_to_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local now = vim.loop.now()
  if (now - self.last_render) < self.throttle_ms then return end
  self.last_render = now

  local lines, canvas = {}, {}
  for r = 1, self.height do
    canvas[r] = {}
    for c = 1, self.width do
      canvas[r][c] = 0x2800
    end
  end

  local current_max = self:get_max_y()

  for i = 1, self.max_points do
    local val = self.data[i]
    local prev = self.data[i - 1] or val
    if i > 1 then self:draw_line_segment(canvas, i, prev, val, current_max) end
  end

  table.insert(lines, pad_label(self:format_value(current_max), "┤"))

  for r = 1, self.height do
    local label_text = ""
    local separator = "│"

    if r == math.floor(self.height / 2) then
      label_text = self:format_value(current_max / 2)
      separator = "┤"
    elseif r == self.height then
      label_text = self:format_value(0)
      separator = "┼"
    end

    local prefix = ""
    if label_text == "" then
      prefix = string.rep(" ", AXIS_COL_WIDTH - 1) .. separator
    else
      prefix = pad_label(label_text, separator)
    end

    local row_str = prefix
    for c = 1, self.width do
      row_str = row_str .. vim.fn.nr2char(canvas[r][c])
    end
    table.insert(lines, row_str)
  end

  -- X-Axis
  local axis_cells = {}
  for _ = 1, self.width do
    table.insert(axis_cells, "─")
  end

  local function write_lbl(text, start_idx)
    for i = 1, #text do
      local char = string.sub(text, i, i)
      if axis_cells[start_idx + i - 1] then axis_cells[start_idx + i - 1] = char end
    end
  end

  write_lbl("60s", 1)
  write_lbl("30s", math.floor(self.width / 2) - 1)
  write_lbl("0s", self.width - 1)

  local bottom_padding = string.rep(" ", AXIS_COL_WIDTH)
  table.insert(lines, bottom_padding .. table.concat(axis_cells))

  -- Add title line at top
  local latest = self.data[#self.data]
  table.insert(lines, 1, string.format(self.title_fmt, self:format_value(latest)))

  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function Graph:push_data(val)
  table.remove(self.data, 1)
  table.insert(self.data, val)

  if self.buf ~= -1 and vim.api.nvim_buf_is_valid(self.buf) then self:render_to_buffer(self.buf) end
  self:flash_update()
end

function Graph:format_value(val)
  if self.type == "bytes" then return format_bytes(val) end
  return format_percent(val)
end

function Graph:draw_line_segment(canvas, col, val1, val2, max_y)
  local max_dots_y = self.height * 4
  local norm1 = math.min(1, math.max(0, val1 / max_y))
  local norm2 = math.min(1, math.max(0, val2 / max_y))
  local y1 = math.floor(norm1 * (max_dots_y - 1))
  local y2 = math.floor(norm2 * (max_dots_y - 1))
  local min_y, max_y_coord = math.min(y1, y2), math.max(y1, y2)

  for dy = min_y, max_y_coord do
    local row = self.height - math.floor(dy / 4)
    if row >= 1 and row <= self.height then
      local sub_y = 3 - (dy % 4)
      local sub_x = (col % 2 == 0) and 2 or 1
      local grid_col = math.ceil(col / 2)
      canvas[row][grid_col] = bit.bor(canvas[row][grid_col], braille_map[sub_y + 1][sub_x])
    end
  end
end

function Graph:open(override_row, override_col)
  if vim.api.nvim_win_is_valid(self.win) then return end

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(self.buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(self.buf, "filetype", "monitorgraph")

  -- Window width = Graph Width + Axis Width + 1 (Buffer)
  local w, h = self.width + AXIS_COL_WIDTH + 1, self.height + 2
  local ui = vim.api.nvim_list_uis()[1]

  local col = override_col or (ui.width - w) / 2
  local row = override_row or (ui.height - h) / 2

  local opts = {
    relative = "editor",
    width = w,
    height = h,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " Connecting... ",
    title_pos = "center",
  }
  self.win = vim.api.nvim_open_win(self.buf, true, opts)

  local hi_name = "GraphHi_" .. tostring(self.buf)
  vim.cmd(string.format("hi %s guifg=%s gui=bold", hi_name, self.color))
  vim.api.nvim_win_set_option(self.win, "winhl", "Normal:" .. hi_name .. ",FloatBorder:Normal")

  -- Updated Regex to match the new dynamic units
  vim.fn.matchadd("Comment", "[0-9.]\\+[KMGTB%s]\\+\\|│\\|─\\|┤\\|┼")

  local close_cmd = string.format(":lua require('monitor_view').close_win(%d)<CR>", self.win)
  vim.api.nvim_buf_set_keymap(self.buf, "n", "q", close_cmd, { noremap = true, silent = true })
  vim.api.nvim_buf_set_keymap(self.buf, "n", "<Esc>", close_cmd, { noremap = true, silent = true })
end

M.Graph = Graph

-- === MODULE INSTANCES ===

local instances = {
  cpu = Graph.new({ type = "percent", title = " CPU (%s) ", color = "#f38ba8" }),
  mem = Graph.new({ type = "bytes", title = " MEM (%s) ", color = "#89b4fa" }),
}

function Graph:flash_update()
  -- Flash floating window if open
  if self.win ~= -1 and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_set_config(self.win, { border = "double" })
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(self.win) then vim.api.nvim_win_set_config(self.win, { border = "rounded" }) end
    end, 50)
  end

  -- Flash any dapui windows showing this buffer
  if self.buf ~= -1 and vim.api.nvim_buf_is_valid(self.buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == self.buf then
        -- Pulse the cursor line briefly
        pcall(vim.api.nvim_win_set_option, win, "cursorline", true)
        vim.defer_fn(function()
          if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_set_option, win, "cursorline", false) end
        end, 100)
      end
    end
  end
end

function M.route_message(method, params)
  if method == "telemetry/cpu" then
    instances.cpu:push_data(params.value)
  elseif method == "telemetry/mem" then
    instances.mem:push_data(params.value)
  end
end

function M.get_cpu_instance() return instances.cpu end

function M.get_mem_instance() return instances.mem end

function M.close_win(win_handle)
  if vim.api.nvim_win_is_valid(win_handle) then vim.api.nvim_win_close(win_handle, true) end
end

function M.toggle_cpu() instances.cpu:open() end
function M.toggle_mem() instances.mem:open() end

function M.open_all()
  local h = instances.cpu.height + 2
  local padding = 1
  local total_h = (h * 2) + padding
  local ui = vim.api.nvim_list_uis()[1]

  local w = instances.cpu.width + AXIS_COL_WIDTH + 1
  local start_col = (ui.width - w) / 2
  local start_row = (ui.height - total_h) / 2

  instances.cpu:open(start_row, start_col)
  instances.mem:open(start_row + h + padding, start_col)
end

vim.api.nvim_create_user_command("CpuGraph", M.toggle_cpu, {})
vim.api.nvim_create_user_command("MemGraph", M.toggle_mem, {})
vim.api.nvim_create_user_command("SysMonitor", M.open_all, {})

return M
