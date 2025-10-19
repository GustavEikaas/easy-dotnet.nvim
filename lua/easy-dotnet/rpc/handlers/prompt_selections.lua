return function(params, response, throw, validate)
  local ok, err = validate({ prompt = "string", choices = "table" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end
  local options = vim.deepcopy(params.choices)

  --BUG: somehow detect picker closing without selecting a value
  require("easy-dotnet.picker").multi_picker(options, function(i)
    local res = vim.tbl_map(function(value) return value.id end, i)
    response(res)
  end, params.prompt, true)
end
