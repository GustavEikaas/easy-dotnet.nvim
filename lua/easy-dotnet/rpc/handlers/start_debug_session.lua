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

  local session = dap.attach({ type = "server", host = host, port = port }, { type = constants.debug_adapter_name, name = constants.debug_adapter_name, request = "attach" }, {})

  if not session then
    local msg = "failed to start debug session"
    throw({ code = -32001, message = msg })
    return
  end
  response(session.id)
end
