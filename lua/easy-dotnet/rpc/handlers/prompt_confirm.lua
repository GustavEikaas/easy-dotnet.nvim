return function(params, response, throw, validate)
  local ok, err = validate({ prompt = "string", defaultValue = "boolean" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end

  local options = {
    { display = "Yes", value = true },
    { display = "No", value = false },
  }
  table.sort(options, function(a) return a.value == params.defaultValue end)
  --BUG: somehow detect picker closing without selecting a value
  require("easy-dotnet.picker").picker(nil, options, function(value) response(value.value) end, params.prompt, false, true)
end
