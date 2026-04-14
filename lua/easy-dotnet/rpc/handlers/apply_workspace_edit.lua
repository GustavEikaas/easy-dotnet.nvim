return function(params, response, throw, _)
  if type(params) ~= "table" or type(params.documentChanges) ~= "table" then
    throw({ code = -32602, message = "Missing required parameter: 'documentChanges'" })
    return
  end

  for _, change in ipairs(params.documentChanges) do
    if change.textDocument and change.textDocument.version == vim.NIL then change.textDocument.version = nil end
  end

  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, params, "utf-8")
  if not ok then
    throw({ code = -32603, message = tostring(err) })
    return
  end

  for _, change in ipairs(params.documentChanges) do
    local uri = change.textDocument and change.textDocument.uri
    if type(uri) == "string" then
      local bufnr = vim.uri_to_bufnr(uri)
      if vim.api.nvim_buf_is_valid(bufnr) then
        local write_ok, write_err = pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("write") end)
        if not write_ok then
          throw({ code = -32603, message = tostring(write_err) })
          return
        end
      end
    end
  end

  response(true)
end
