---@alias SearchState "idle" | "searching"

local ns_id = require("easy-dotnet.constants").ns_id
local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local current_frame = 1
local M = {
  active_symbols = {
    "class",
    "record",
  },
  bufs = {},
  windows = {},
  state = "idle", -- "idle" | "searching"
  timer = nil,
  result_buffer = {},
}

local symbol_types = {
  "class",
  "struct",
  "record",
  "recordstruct",
  "interface",
  "enum",
  "delegate",
  "method",
  "property",
  "field",
  "event",
  "local",
  "parameter",
  "namespace",
}

local config = {
  width = math.floor(vim.o.columns * 1),
  height = math.floor(vim.o.lines * 0.9),
  sidebar_width = 18,
  bottom_height = 1,
}

function M.toggle_symbol_by_index(i)
  local index = i
  if index == 0 then index = 10 end -- map '0' key to 10th symbol

  local sym = symbol_types[index]
  if not sym then return end

  local exists = vim.tbl_contains(M.active_symbols, sym)
  if exists then
    -- Remove it
    M.active_symbols = vim.tbl_filter(function(s) return s ~= sym end, M.active_symbols)
  else
    -- Add it
    table.insert(M.active_symbols, sym)
  end

  M.fill_symbols()
end

-- Create a floating window
local function create_win(width, height, row, col, opts)
  local buf = vim.api.nvim_create_buf(false, true) -- no file, scratch
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    focusable = true,
    noautocmd = true,
  })
  if opts and opts.modifiable == false then vim.api.nvim_buf_set_option(buf, "modifiable", false) end
  return buf, win
end

-- Fill left sidebar buffer with the symbol types list
function M.fill_symbols()
  if not M.bufs.symbols or not vim.api.nvim_buf_is_valid(M.bufs.symbols) then return end

  local lines = {}
  local highlights = {}

  for i, sym in ipairs(symbol_types) do
    table.insert(lines, string.format("g%-2d  %s", i, sym))
    -- table.insert(lines, string.format("g%2d %s", i, sym))
    if vim.tbl_contains(M.active_symbols, sym) then
      table.insert(highlights, { line = i - 1, hl = "Question" }) -- zero-indexed
    end
  end

  vim.api.nvim_buf_set_option(M.bufs.symbols, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.bufs.symbols, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(M.bufs.symbols, -1, 0, -1)

  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(M.bufs.symbols, -1, h.hl, h.line, 0, -1)
  end

  vim.api.nvim_buf_set_option(M.bufs.symbols, "modifiable", false)
end

function M.open()
  M.symbols = symbol_types
  local width, height = config.width, config.height
  local sidebar_w = config.sidebar_width
  local bottom_h = config.bottom_height
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  M.bufs.symbols, M.windows.symbols = create_win(sidebar_w, height - bottom_h, row, col)
  vim.api.nvim_buf_set_option(M.bufs.symbols, "modifiable", false)

  M.bufs.results, M.windows.results = create_win(width - sidebar_w - 3, height - bottom_h, row, col + sidebar_w + 3)
  vim.api.nvim_buf_set_option(M.bufs.results, "modifiable", false)

  M.bufs.input, M.windows.input = create_win(width, bottom_h, row + height - bottom_h, col)
  vim.api.nvim_buf_set_option(M.bufs.input, "modifiable", true)
  vim.api.nvim_buf_set_option(M.bufs.input, "buftype", "prompt")

  vim.fn.prompt_setprompt(M.bufs.input, "Search: ")
  vim.api.nvim_buf_set_option(M.bufs.input, "buftype", "nofile")

  for i, sym in ipairs(symbol_types) do
    vim.keymap.set("n", string.format("g%d", i), function()
      if vim.list_contains(M.active_symbols, sym) and #M.active_symbols > 1 then
        M.active_symbols = vim.tbl_filter(function(x) return x ~= sym end, M.active_symbols)
      else
        table.insert(M.active_symbols, sym)
      end

      M.fill_symbols()
    end, { noremap = true, silent = true, buffer = M.bufs.input })
  end

  vim.keymap.set("i", "<CR>", function() M.on_search() end, { buffer = M.bufs.input, noremap = true, silent = true })
  vim.keymap.set("i", "<C-c>", function() M.close() end, { buffer = M.bufs.input, noremap = true, silent = true })
  vim.keymap.set("n", "q", function() M.close() end, { buffer = M.bufs.input, noremap = true, silent = true })

  vim.api.nvim_set_current_win(M.windows.input)
  vim.cmd("startinsert!")

  M.fill_symbols()
end

function M.close()
  for _, win in pairs(M.windows) do
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  M.windows = {}
  M.bufs = {}
end

function M.on_search()
  local lines = vim.api.nvim_buf_get_lines(M.bufs.input, 0, -1, false)
  local query = vim.trim(lines[1]:gsub("^Search: ", ""))
  print("Search query:", query)

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    M.start_spinner_statusline_style(M.bufs.input)
    M.result_buffer = {}
    M.redraw_results()
    local unsub = client._client.subscribe_notifications(function(a, b)
      table.insert(M.result_buffer, b)
      M.redraw_results()
    end)
    client:symbol_search(
      query,
      { "local", "class", "record" },
      -- { "./EasyDotnet.Tool/EasyDotnet.csproj" }
      {
        "./src/NeovimDebugProject.xUnit/NeovimDebugProject.xUnit.csproj",
        "./src/NeovimDebugProject.Web/NeovimDebugProject.Web.csproj",
        "./src/NeovimDebugProject.Test/NeovimDebugProject.Test.csproj",
        "./src/NeovimDebugProject.Rzls/NeovimDebugProject.Rzls.csproj",
        "./src/NeovimDebugProject.NUnitTestProject/NeovimDebugProject.NUnitTestProject.csproj",
        "./src/NeovimDebugProject.MSTest/NeovimDebugProject.MSTest.csproj",
      },
      function()
        -- M.redraw_results(dummy_res)
        M.stop_spinner(M.bufs.input)
        unsub()
      end
    )
  end)
end

function M.start_spinner_statusline_style(buf)
  M.timer = vim.loop.new_timer()
  M.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      local line_count = vim.api.nvim_buf_line_count(buf)
      local last_line = line_count - 1

      -- Clear previous spinner
      vim.api.nvim_buf_clear_namespace(buf, ns_id, last_line, last_line + 1)

      -- Get the actual line content to calculate position
      local line_content = vim.api.nvim_buf_get_lines(buf, last_line, last_line + 1, false)[1] or ""
      local wins = vim.fn.win_findbuf(buf)

      if #wins > 0 then
        local win = wins[1]
        local width = vim.api.nvim_win_get_width(win)

        -- Position spinner with some padding from the right
        local col_pos = math.max(0, width - 3) -- 3 chars from right edge

        vim.api.nvim_buf_set_extmark(buf, ns_id, last_line, #line_content, {
          virt_text = { { string.rep(" ", math.max(0, col_pos - #line_content)) .. spinner_frames[current_frame], "Comment" } },
          virt_text_pos = "overlay",
        })
      end

      current_frame = current_frame % #spinner_frames + 1
    end)
  )
end

function M.stop_spinner(buf)
  if M.timer then
    M.timer:stop()
    M.timer:close()
    M.timer = nil
  end

  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
end

function M.redraw_results()
  if not M.bufs.results or not vim.api.nvim_buf_is_valid(M.bufs.results) then return end

  local lines = {}

  for _, result in ipairs(M.result_buffer) do
    local filename = vim.fn.fnamemodify(result.filePath, ":t") -- just the file name
    local line = string.format("%s %-25s (%s:%d)", result.kind, result.name, filename, result.line)
    table.insert(lines, line)
  end

  vim.api.nvim_buf_set_option(M.bufs.results, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.bufs.results, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.bufs.results, "modifiable", false)
end

return M

---@class SymbolResult
---@field name string
---@field kind string
---@field filePath string
---@field line integer
