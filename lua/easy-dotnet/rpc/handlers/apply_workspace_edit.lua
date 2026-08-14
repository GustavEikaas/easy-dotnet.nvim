---@param params lsp.WorkspaceEdit
return function(params, response, throw, _)
  if type(params) ~= "table" or type(params.documentChanges) ~= "table" then
    throw({ code = -32602, message = "Missing required parameter: 'documentChanges'" })
    return
  end

  local client_versions = vim.lsp.util.buf_versions or {}

  -- backwards compatibility with easy-dotnet < 3.4.18
  local contains_create_file_edit = vim.iter(params.documentChanges):any(function(change) return change.kind == "create" end)

  for _, change in ipairs(params.documentChanges) do
    if change.textDocument and change.textDocument.uri then
      local bufnr = not contains_create_file_edit and vim.uri_to_bufnr(change.textDocument.uri) or vim.fn.bufnr(vim.uri_to_fname(change.textDocument.uri))
      if bufnr ~= -1 then
        local current_ver
        if type(client_versions) == "function" then
          current_ver = client_versions()[bufnr]
        else
          current_ver = client_versions[bufnr]
        end
        change.textDocument.version = current_ver or 0
      end
    end
  end

  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, params, "utf-8")
  if not ok then
    throw({ code = -32603, message = tostring(err) })
    return
  end

  for _, change in ipairs(params.documentChanges) do
    local uri = change.textDocument and change.textDocument.uri
    if type(uri) == "string" then
      local bufnr = vim.fn.bufnr(vim.uri_to_fname(uri))
      if vim.api.nvim_buf_is_valid(bufnr) then pcall(vim.api.nvim_buf_call, bufnr, function() vim.cmd("silent! update") end) end
    end
  end

  response(true)
end
