return function(params, response, throw, validate)
  local session_id = params.sessionId

  local ok, err = validate({ sessionId = "number" })
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

  vim.print(params)

  ---@type dap.Session
  local session = vim.iter(dap.sessions()):find(function(i) return i.id == session_id end)
  vim.print("Stopping session " .. session.id)
  session:close()
  response(true)
end
