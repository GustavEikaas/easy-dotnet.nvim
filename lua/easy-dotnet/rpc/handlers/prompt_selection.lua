return function(params, response, throw, validate)
  local ok, err = validate({ prompt = "string", choices = "table" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end
  ---@type RPC_PromptSelection[]
  local options = params.choices
  require("easy-dotnet.picker").picker(nil, options, function(i) response(i.id) end, params.prompt, true, true)
end
