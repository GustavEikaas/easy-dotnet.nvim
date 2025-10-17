return function(params, response, throw, validate)
  local path = params.path
  local line = params.lineNumber

  local ok, err = validate({ lineNumber = "number", path = "file" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local dap_ok, dap = pcall(require, "dap")
  if not dap_ok then
    local msg = "nvim-dap is not installed"
    throw({ code = -32001, message = msg })
    return
  end

  local full_path = vim.fn.expand(path)
  vim.cmd.edit(vim.fn.fnameescape(full_path))
  vim.api.nvim_win_set_cursor(0, { line, 0 })

  local bp_ok, bp_err = pcall(dap.set_breakpoint)
  if not bp_ok then
    local msg = "Failed to set breakpoint: " .. tostring(bp_err)
    throw({ code = -32002, message = msg })
    return
  end

  response(true)
end
