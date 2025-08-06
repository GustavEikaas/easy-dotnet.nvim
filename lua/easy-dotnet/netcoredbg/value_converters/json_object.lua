local unwrap_key = "Dictionary"
---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^System%.Text%.Json%.Nodes%.JsonObject$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    ---@type Variable
    local var_ref = nil

    for _, property in ipairs(vars) do
      if property.name == unwrap_key then var_ref = property end
    end

    if not var_ref then error(string.format("Failed to get %s from JsonObject", unwrap_key)) end

    local netcoredbg = require("easy-dotnet.netcoredbg")

    netcoredbg.fetch_variables(
      var_ref.variablesReference,
      0,
      function(entries) require("easy-dotnet.netcoredbg.value_converters.dictionaries").extract(frame_id, entries, var_path .. "." .. unwrap_key, var_ref.type, cb) end
    )
  end,
}
