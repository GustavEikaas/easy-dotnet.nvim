return function(params, response, throw, validate)
  local ok, err = validate({ prompt = "string" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end
  vim.ui.input({ prompt = params.prompt, default = params.defaultValue }, function(input)
    if not input then
      throw("User aborted")
      return
    end
    response(input)
  end)
end
