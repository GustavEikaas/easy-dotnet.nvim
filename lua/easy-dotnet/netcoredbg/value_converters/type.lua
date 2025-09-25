---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.RuntimeType$") ~= nil
  end,
  extract = function(_, vars, var_path, _, cb)
    require("easy-dotnet.netcoredbg.value_converters").vars_to_table(var_path, vars, function(val) cb(val, string.format("{ Name = %s, FullName = %s}", val.Name.value, val.FullName.value)) end)
  end,
}
