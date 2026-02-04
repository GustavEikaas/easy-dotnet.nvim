---@class easy-dotnet.Roslyn.ReferenceRange
---@field start { line: number, character: number }
---@field end { line: number, character: number }

---@class easy-dotnet.Roslyn.ReferenceItem
---@field filename string The full path to the file
---@field line number The 1-indexed line number
---@field preview string The text preview of the line
---@field range easy-dotnet.Roslyn.ReferenceRange The start and end positions of the reference

---@param client vim.lsp.Client
---@param cb fun(res: easy-dotnet.Roslyn.ReferenceItem[]): nil
local function get_preview_references(client, file_uri, position, bufnr, cb)
  local params = {
    textDocument = { uri = file_uri },
    position = position,
    context = { includeDeclaration = false },
  }

  client:request("textDocument/references", params, function(err, result)
    if err then
      vim.notify("[easy-dotnet] peekReferences error: " .. err.message, vim.log.levels.ERROR)
      return
    end

    if not result or vim.tbl_isempty(result) then
      vim.notify("[easy-dotnet] No references found", vim.log.levels.INFO)
      return
    end

    ---@type easy-dotnet.Roslyn.ReferenceItem[]
    local items = vim
      .iter(result)
      :map(function(ref)
        local uri = ref.uri or ref.targetUri
        if not uri then return nil end

        local fname = vim.uri_to_fname(uri)
        local lnum = ref.range.start.line + 1

        local buf = vim.fn.bufadd(fname)
        vim.fn.bufload(buf)
        local line_text = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""

        return {
          filename = fname,
          line = lnum,
          preview = line_text,
          range = ref.range,
        }
      end)
      :totable()

    cb(items)
  end, bufnr)
end

---@param references easy-dotnet.Roslyn.ReferenceItem[]
local function open_references_float(references)
  local bg_color = "#1e1e1e"
  local active_bg = "#252526"
  local accent = "#007acc"

  vim.api.nvim_set_hl(0, "PeekWinBar", { bg = bg_color, fg = "#ffffff", bold = true })
  vim.api.nvim_set_hl(0, "PeekSideBar", { bg = bg_color, fg = "#cccccc" })
  vim.api.nvim_set_hl(0, "PeekMain", { bg = active_bg })
  vim.api.nvim_set_hl(0, "PeekBorder", { fg = accent, bg = "NONE" })
  vim.api.nvim_set_hl(0, "PeekTitle", { fg = "#ffffff", bg = accent, bold = true })
  vim.api.nvim_set_hl(0, "PeekHint", { fg = "#858585", bg = bg_color, italic = true })
  vim.api.nvim_set_hl(0, "PeekListActive", { bg = "#094771", fg = "#ffffff" })

  if #references == 0 then return end

  local total_width = math.floor(vim.o.columns * 0.85)
  local total_height = math.floor(vim.o.lines * 0.7)
  local list_width = 32
  local preview_width = total_width - list_width

  local list_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = vim.api.nvim_create_buf(false, true)

  local display_lines = vim.iter(references):map(function(item) return string.format(" %-20s %4d ", vim.fn.fnamemodify(item.filename, ":t"), item.line) end):totable()
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, display_lines)

  local row = math.floor((vim.o.lines - total_height) / 2)
  local col = math.floor((vim.o.columns - total_width) / 2)

  local preview_win = vim.api.nvim_open_win(preview_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = preview_width,
    height = total_height,
    border = { "╭", "─", "┬", "│", "┴", "─", "╰", "│" },
    title = { { " Peek Preview ", "PeekTitle" } },
    title_pos = "left",
  })

  local list_win = vim.api.nvim_open_win(list_buf, false, {
    relative = "editor",
    row = row,
    col = col + preview_width + 1,
    width = list_width,
    height = total_height,
    border = { "─", "─", "╮", "│", "╯", "─", "─", "" },
  })

  vim.wo[preview_win].winhighlight = "Normal:PeekMain,FloatBorder:PeekBorder,WinBar:PeekWinBar"
  vim.wo[list_win].winhighlight = "Normal:PeekSideBar,FloatBorder:PeekBorder,CursorLine:PeekListActive"
  vim.wo[list_win].cursorline = true

  local current_idx = 1

  local function update_view()
    if not vim.api.nvim_win_is_valid(preview_win) then return end
    local item = references[current_idx]

    local lines = vim.fn.readfile(item.filename)
    vim.bo[preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
    vim.bo[preview_buf].modifiable = false
    vim.bo[preview_buf].filetype = vim.filetype.match({ filename = item.filename }) or "text"

    vim.api.nvim_win_set_cursor(preview_win, { item.line, item.range.start.character })
    vim.api.nvim_command("normal! zz")
    vim.api.nvim_win_set_cursor(list_win, { current_idx, 0 })

    local filename = vim.fn.fnamemodify(item.filename, ":~:.")
    vim.wo[preview_win].winbar = string.format("%%#PeekWinBar#  󰈙 %s  %%#PeekHint#  󰮫 Tab/S-Tab  <CR> Open  q Close", filename)

    local ns = vim.api.nvim_create_namespace("peek_hl")
    vim.api.nvim_buf_clear_namespace(preview_buf, ns, 0, -1)
    vim.api.nvim_buf_add_highlight(preview_buf, ns, "Visual", item.line - 1, 0, -1)
  end

  local function cycle(delta)
    current_idx = current_idx + delta
    if current_idx > #references then current_idx = 1 end
    if current_idx < 1 then current_idx = #references end
    update_view()
  end

  local function close_all()
    if vim.api.nvim_win_is_valid(preview_win) then vim.api.nvim_win_close(preview_win, true) end
    if vim.api.nvim_win_is_valid(list_win) then vim.api.nvim_win_close(list_win, true) end
  end

  local map_opts = { buffer = preview_buf, silent = true, nowait = true }
  vim.keymap.set("n", "<Tab>", function() cycle(1) end, map_opts)
  vim.keymap.set("n", "<S-Tab>", function() cycle(-1) end, map_opts)
  vim.keymap.set("n", "<CR>", function()
    local item = references[current_idx]
    close_all()
    vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
    vim.api.nvim_win_set_cursor(0, { item.line, item.range.start.character })
  end, map_opts)
  vim.keymap.set("n", "q", close_all, map_opts)
  vim.keymap.set("n", "<Esc>", close_all, map_opts)

  update_view()
end

return function(command, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then
    vim.notify("[easy-dotnet] No LSP client for peekReferences", vim.log.levels.ERROR)
    return
  end

  local file_uri = command.arguments[1]
  local pos = command.arguments[2]
  get_preview_references(client, file_uri, pos, ctx.bufnr, open_references_float)
end
