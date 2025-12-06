local constants = require("easy-dotnet.constants")

return function(params, response, throw, validate)
  local host = params.host
  local port = params.port

  local ok, err = validate({ host = "string", port = "number" })
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

  dap.run({ type = constants.debug_adapter_name, name = constants.debug_adapter_name, request = "attach", host = host, port = port }, { new = true })

  local session = dap.session()
  if not session then
    throw({ code = -32001, message = "failed to start debug session" })
    return
  end

  response(session.id)
end
