return function(params, response, throw, validate)
  local ok, err = validate({ prompt = "string", choices = "table" })
  if not ok then
    throw({ code = -32602, message = err })
    return
  end
  local options = vim.deepcopy(params.choices)
  local defaultId = params.defaultSelectionId

  if defaultId then vim.iter(options):map(function(option)
    if option.id == defaultId then option.display = option.display .. " (default)" end
    return option
  end) end

  if defaultId then table.sort(options, function(a, b)
    if a.id == defaultId then return true end
    if b.id == defaultId then return false end
    return false
  end) end

  --BUG: somehow detect picker closing without selecting a value
  require("easy-dotnet.picker").picker(nil, options, function(i) response(i.id) end, params.prompt, true, true)
end
