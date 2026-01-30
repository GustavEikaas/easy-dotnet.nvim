local M = {}

-- === CONFIGURATION ===
local AXIS_COL_WIDTH = 12
local THROTTLE_MS = 33 -- ~30 FPS
local HISTORY_SIZE = 600 -- Store enough data for ~300 character wide windows

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

local function pad_label(text, separator)
  local content_width = #text + 2
  local padding = AXIS_COL_WIDTH - content_width
  return string.rep(" ", math.max(0, padding)) .. text .. " " .. separator
end

local braille_map = { { 0x1, 0x8 }, { 0x2, 0x10 }, { 0x4, 0x20 }, { 0x40, 0x80 } }

-- === GRAPH CLASS ===

local Graph = {}
Graph.__index = Graph

function Graph.new(opts)
  local self = setmetatable({}, Graph)
  self.type = opts.type or "percent"
  self.title_fmt = opts.title or " Graph (%s) "
  self.color = opts.color or "CpuNormal"

  self.active_buffers = {}
  self.data = {}
  -- Fixed large history buffer (not tied to render width)
  self.max_points = HISTORY_SIZE

  for _ = 1, self.max_points do
    table.insert(self.data, 0)
  end

  self.last_render = 0
  return self
end

function Graph:track_buffer(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then self.active_buffers[buf] = true end
end

function Graph:get_max_y(subset_data)
  if self.type == "percent" then return 100 end
  local max_val = 1
  -- Only scale based on visible data to avoid flat lines from old spikes
  for _, v in ipairs(subset_data) do
    if v > max_val then max_val = v end
  end
  return max_val * 1.1
end

function Graph:format_value(val) return self.type == "bytes" and format_bytes(val) or format_percent(val) end

function Graph:draw_line_segment(canvas, col, val1, val2, max_y, height)
  local max_dots_y = height * 4
  local norm1 = math.min(1, math.max(0, val1 / max_y))
  local norm2 = math.min(1, math.max(0, val2 / max_y))
  local y1 = math.floor(norm1 * (max_dots_y - 1))
  local y2 = math.floor(norm2 * (max_dots_y - 1))

  local min_y, max_y_coord = math.min(y1, y2), math.max(y1, y2)
  for dy = min_y, max_y_coord do
    local row = height - math.floor(dy / 4)
    if row >= 1 and row <= height then
      local sub_y = 3 - (dy % 4)
      local sub_x = (col % 2 == 0) and 2 or 1
      -- Ensure we don't write outside canvas due to float math
      local grid_col = math.ceil(col / 2)
      if canvas[row] and canvas[row][grid_col] then canvas[row][grid_col] = bit.bor(canvas[row][grid_col], braille_map[sub_y + 1][sub_x]) end
    end
  end
end

function Graph:render_to_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  -- 1. DETECT WINDOW SIZE
  -- If buffer is not visible in any window, skip rendering to save CPU
  local win_ids = vim.fn.win_findbuf(buf)
  if #win_ids == 0 then return end

  local win = win_ids[1] -- Use the first window displaying this buffer
  local win_width = vim.api.nvim_win_get_width(win)
  local win_height = vim.api.nvim_win_get_height(win)

  -- Calculate Canvas Dimensions
  -- Width: Window Width - Axis Column
  -- Height: Window Height - Title Line (1) - X-Axis Line (1)
  local canvas_width = math.max(10, win_width - AXIS_COL_WIDTH)
  local canvas_height = math.max(2, win_height - 2)

  -- Throttling
  local now = vim.loop.now()
  if (now - self.last_render) < THROTTLE_MS then return end
  self.last_render = now

  -- 2. PREPARE DATA SLICE
  -- We need (canvas_width * 2) data points.
  -- Get them from the end of self.data
  local points_needed = canvas_width * 2
  local start_idx = #self.data - points_needed + 1
  if start_idx < 1 then start_idx = 1 end

  local visible_data = {}
  for i = start_idx, #self.data do
    table.insert(visible_data, self.data[i])
  end

  -- 3. INITIALIZE GRID
  local lines, canvas = {}, {}
  for r = 1, canvas_height do
    canvas[r] = {}
    for c = 1, canvas_width do
      canvas[r][c] = 0x2800
    end
  end

  local current_max = self:get_max_y(visible_data)

  -- 4. PLOT DATA
  for i = 1, #visible_data do
    local val = visible_data[i]
    local prev = visible_data[i - 1] or val
    -- Only draw connection if i > 1 within visible set
    if i > 1 then self:draw_line_segment(canvas, i, prev, val, current_max, canvas_height) end
  end

  -- 5. CONSTRUCT STRINGS (Y-Axis + Graph)
  table.insert(lines, pad_label(self:format_value(current_max), "┤"))

  for r = 1, canvas_height do
    local label = ""
    local sep = "│"
    if r == math.floor(canvas_height / 2) then
      label = self:format_value(current_max / 2)
      sep = "┤"
    elseif r == canvas_height then
      label = self:format_value(0)
      sep = "┼"
    end

    local prefix = (label == "") and (string.rep(" ", AXIS_COL_WIDTH - 1) .. sep) or pad_label(label, sep)

    local row_str = prefix
    for c = 1, canvas_width do
      row_str = row_str .. vim.fn.nr2char(canvas[r][c])
    end
    table.insert(lines, row_str)
  end

  -- 6. X-AXIS
  local axis_str = string.rep("─", canvas_width)
  -- Inject labels relative to the new width
  local function inject(s, t, offset_right)
    local idx = #s - offset_right
    if idx < 1 or idx > #s then return s end
    return string.sub(s, 1, idx - 1) .. t .. string.sub(s, idx + #t)
  end

  if canvas_width > 20 then
    axis_str = inject(axis_str, "0s", 1)
    axis_str = inject(axis_str, "30s", math.floor(canvas_width / 2))
    axis_str = inject(axis_str, "60s", canvas_width - 4)
  end

  table.insert(lines, string.rep(" ", AXIS_COL_WIDTH) .. axis_str)

  -- 7. TITLE
  local latest = self.data[#self.data]
  table.insert(lines, 1, string.format(self.title_fmt, self:format_value(latest)))

  -- 8. WRITE TO BUFFER
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function Graph:push_data(val)
  table.remove(self.data, 1)
  table.insert(self.data, val)

  -- Update all registered buffers
  for buf, _ in pairs(self.active_buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      self:render_to_buffer(buf)
    else
      self.active_buffers[buf] = nil
    end
  end
end

-- === MODULE STATE ===

local instances = {
  cpu = Graph.new({ type = "percent", title = " CPU (%s) ", color = "#f38ba8" }),
  mem = Graph.new({ type = "bytes", title = " MEM (%s) ", color = "#89b4fa" }),
}

-- === PUBLIC API ===

function M.route_message(method, params)
  if method == "telemetry/cpu" then
    instances.cpu:push_data(params.value)
  elseif method == "telemetry/mem" then
    instances.mem:push_data(params.value)
  end
end

function M.get_graphs() return instances end

return M
