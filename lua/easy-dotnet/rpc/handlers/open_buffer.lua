return function(params, response, throw, validate)
  local ok, err = validate({ path = "file" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local full_path = vim.fn.expand(params.path)
  vim.cmd.edit(vim.fn.fnameescape(full_path))
  response(true)
end
