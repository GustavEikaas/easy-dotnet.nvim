return function(params, response, throw, validate)
  local ok, err = validate({ path = "string" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local full_path = vim.fn.expand(params.path)

  if vim.fn.filereadable(full_path) == 0 then
    throw({ code = -32000, message = "File not found: " .. full_path })
    return
  end

  vim.cmd.edit(vim.fn.fnameescape(full_path))
  response(true)
end
