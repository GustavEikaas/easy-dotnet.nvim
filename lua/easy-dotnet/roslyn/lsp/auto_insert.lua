--- Wires up Roslyn's `textDocument/_vs_onAutoInsert` so that typing the third `/` of a
--- `///` doc-comment expands into a full XML documentation stub (`<summary>`, one
--- `<param>` per parameter, `<returns>`, etc.), with the cursor placed inside `<summary>`.
---
--- This is a VS-specific LSP extension (`_vs_` prefix). Neovim's built-in client never
--- calls it on its own, so we trigger it manually on the `/` keypress and apply the
--- snippet the server returns.
local M = {}

local AUTO_INSERT_METHOD = "textDocument/_vs_onAutoInsert"

--- Convert a UTF (offset-encoding) column to a byte column on the given 0-indexed row.
---@param bufnr integer
---@param row0 integer 0-indexed row
---@param char_col integer column in the server's offset encoding
---@param encoding string "utf-8" | "utf-16" | "utf-32"
---@return integer byte_col
local function to_byte_col(bufnr, row0, char_col, encoding)
  local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1] or ""
  local ok, byte = pcall(vim.str_byteindex, line, encoding, char_col)
  if ok then return byte end
  return math.min(char_col, #line)
end

--- We deliberately avoid `vim.snippet.expand`, which re-indents multi-line snippets and would fight the whitespace Roslyn already baked in.
---@param text_edit lsp.TextEdit
---@param bufnr integer
---@param encoding string
local function apply_snippet_edit(text_edit, bufnr, encoding)
  local body = (text_edit.newText or ""):gsub("\r\n", "\n")
  local caret_idx = body:find("$0", 1, true)

  local before = caret_idx and body:sub(1, caret_idx - 1) or body
  text_edit.newText = caret_idx and (before .. body:sub(caret_idx + 2)) or body

  vim.lsp.util.apply_text_edits({ text_edit }, bufnr, encoding)

  if not caret_idx then return end

  local start_pos = text_edit.range.start
  local newline_count = select(2, before:gsub("\n", ""))
  local last_segment = before:match("[^\n]*$") or ""
  if newline_count == 0 then
    local start_col = to_byte_col(bufnr, start_pos.line, start_pos.character, encoding)
    vim.api.nvim_win_set_cursor(0, { start_pos.line + 1, start_col + #last_segment })
  else
    vim.api.nvim_win_set_cursor(0, { start_pos.line + newline_count + 1, #last_segment })
  end
end

--- Ask Roslyn to expand the `///` at the cursor and apply the response.
---@param client vim.lsp.Client
---@param bufnr integer
local function request_doc_comment(client, bufnr)
  if vim.api.nvim_get_current_buf() ~= bufnr then return end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  local before_cursor = vim.api.nvim_get_current_line():sub(1, col)
  if not before_cursor:match("^%s*///$") then return end

  local params = {
    _vs_textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    _vs_position = { line = row - 1, character = col },
    _vs_ch = "/",
    _vs_options = {
      tabSize = vim.bo[bufnr].shiftwidth ~= 0 and vim.bo[bufnr].shiftwidth or vim.bo[bufnr].tabstop,
      insertSpaces = vim.bo[bufnr].expandtab,
    },
  }

  client:request(AUTO_INSERT_METHOD, params, function(err, result)
    if err or not result or not result._vs_textEdit then return end
    if vim.api.nvim_get_current_buf() ~= bufnr then return end

    apply_snippet_edit(result._vs_textEdit, bufnr, client.offset_encoding or "utf-16")
  end, bufnr)
end

--- Register the `///` auto-insert trigger for a C# buffer.
---@param client vim.lsp.Client
---@param bufnr integer
function M.setup(client, bufnr)
  local caps = client.server_capabilities
  if not (caps and caps._vs_onAutoInsertProvider) then return end

  local group = vim.api.nvim_create_augroup(string.format("easy-dotnet-roslyn-autoinsert-%d-%d", client.id, bufnr), { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = group,
    buffer = bufnr,
    desc = "Roslyn: expand /// into an XML doc comment",
    callback = function()
      if vim.v.char ~= "/" then return end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then request_doc_comment(client, bufnr) end
      end)
    end,
  })
end

return M
