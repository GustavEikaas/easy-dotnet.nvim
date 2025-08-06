---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^System%.Text%.Json%.Nodes%.JsonArray$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb)
    ---@type Variable
    local var_ref = nil

    for _, entry in ipairs(vars) do
      if entry.name == "List" then var_ref = entry end
    end

    if var_ref then
      require("easy-dotnet.netcoredbg").fetch_variables(
        var_ref.variablesReference,
        0,
        function(children) require("easy-dotnet.netcoredbg.value_converters.list").extract(frame_id, children, var_path .. ".List", var_ref.type, cb) end
      )
    end
  end,
}
