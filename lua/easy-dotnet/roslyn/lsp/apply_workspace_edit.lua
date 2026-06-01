---Applies a `WorkspaceEdit` from an LSP server, notifies the user of changes,
---and writes affected buffers to disk.
---
---This function:
---1. Applies the edit via `vim.lsp.util.apply_workspace_edit`.
---2. Counts the number of edits and affected files.
---3. Notifies the user with a summary message.
---4. Writes each changed buffer to disk if it exists.
---
---@param edit lsp.WorkspaceEdit?  # The workspace edit provided by the LSP server (may be nil).
---@param client vim.lsp.Client    # The LSP client issuing the edit.
---@return nil
return function(edit, client)
  if not edit then return end

  vim.lsp.util.apply_workspace_edit(edit, client.offset_encoding)

  local x = { files = {}, edit_count = 0 }

  if edit.documentChanges then
    for _, change in ipairs(edit.documentChanges) do
      if change.textDocument and change.textDocument.uri then
        table.insert(x.files, change.textDocument.uri)
        x.edit_count = x.edit_count + #(change.edits or {})
      end
    end
  elseif edit.changes then
    for uri, edits in pairs(edit.changes) do
      table.insert(x.files, uri)
      x.edit_count = x.edit_count + #(edits or {})
    end
  end

  local msg = (#x.files > 1) and string.format("Performed %d edits across %d files", x.edit_count, #x.files) or string.format("Performed %d edits", x.edit_count)
  vim.notify(msg)

  vim.iter(x.files):map(vim.uri_to_fname):map(function(fname) return vim.fn.bufnr(fname, true) end):filter(function(bufnr) return bufnr ~= -1 end):each(function(bufnr)
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent write") end)
  end)
end
