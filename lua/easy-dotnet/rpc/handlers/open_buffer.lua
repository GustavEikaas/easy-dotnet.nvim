return function(params, response, throw, validate)
  local ok, err = validate({ path = "file" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local render = require("easy-dotnet.test-runner.render")
  if render.close then render.close() end

  local maybe_line = params.line
  local full_path = vim.fn.expand(params.path)

  vim.cmd.edit(vim.fn.fnameescape(full_path))

  if maybe_line and type(maybe_line) == "number" then
    pcall(vim.api.nvim_win_set_cursor, 0, { maybe_line, 0 })
    vim.cmd("normal! zz")
  end

  response(true)
end
