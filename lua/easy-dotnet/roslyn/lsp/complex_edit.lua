local apply_workspace_edit = require("easy-dotnet.roslyn.lsp.apply_workspace_edit")

--- Converts a global offset (0-indexed) to a Neovim cursor position {row, col}
--- @param bufnr integer
--- @param global_offset integer
--- @param encoding string "utf-16" | "utf-32" | "utf-8"
local function move_to_global_offset(bufnr, global_offset, encoding)
  local target = math.max(0, global_offset - 1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for i = 0, line_count - 1 do
    local line_start = vim.api.nvim_buf_get_offset(bufnr, i)
    local line_end = vim.api.nvim_buf_get_offset(bufnr, i + 1)
    if target < line_end then
      local relative_utf_offset = target - line_start
      local line_text = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1] or ""
      local ok, byte_col = pcall(vim.str_byteindex, line_text, encoding, relative_utf_offset)

      if not ok then return end

      local win = vim.fn.bufwinid(bufnr)
      if win ~= -1 then vim.api.nvim_win_set_cursor(win, { i + 1, byte_col }) end
      return
    end
  end
end

---@param ctx CommandContext
return function(data, ctx)
  local textDocument, edit, is_snippet, new_offset = unpack(data.arguments)
  if is_snippet then
    vim.notify("[easy-dotnet] ComplexEdit: Snippets not supported.", vim.log.levels.ERROR)
    return
  end

  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then return end

  ---@type lsp.WorkspaceEdit
  local workspace_edit = { changes = { [textDocument.uri] = { edit } } }

  apply_workspace_edit(workspace_edit, client)

  if new_offset and new_offset >= 0 then
    local bufnr = vim.uri_to_bufnr(textDocument.uri)
    local encoding = client.offset_encoding or "utf-16"

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then move_to_global_offset(bufnr, new_offset, encoding) end
    end)
  end
end
