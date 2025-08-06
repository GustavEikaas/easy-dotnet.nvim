---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^Newtonsoft%.Json%.Linq%.JArray$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    ---@type Variable
    local var_ref = nil

    for _, entry in ipairs(vars) do
      if entry.name == "_values" then var_ref = entry end
    end

    if var_ref then
      require("easy-dotnet.netcoredbg").fetch_variables(
        var_ref.variablesReference,
        0,
        function(children) require("easy-dotnet.netcoredbg.value_converters.list").extract(frame_id, children, var_path .. "._values", var_ref.type, cb) end
      )
    end
  end,
}
