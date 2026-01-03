---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^Newtonsoft%.Json%.Linq%.JObject$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    ---@type easy-dotnet.Debugger.Variable
    local var_ref = nil

    for _, property in ipairs(vars) do
      if property.name == "_properties" then var_ref = property end
    end

    if not var_ref then error("failed to get _properties from JObject") end
    local netcoredbg = require("easy-dotnet.netcoredbg")
    netcoredbg.fetch_variables(var_ref.variablesReference, 1, function(entries)
      for _, value in ipairs(entries) do
        if value.name == "_dictionary" then
          require("easy-dotnet.netcoredbg.value_converters.dictionaries").extract(frame_id, value.children, var_path .. "._properties._dictionary", var_ref.type, cb)
        end
      end
    end)
  end,
}
