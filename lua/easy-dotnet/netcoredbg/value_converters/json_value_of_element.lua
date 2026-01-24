---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^System%.Text%.Json%.Nodes%.JsonValueOfElement$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb) require("easy-dotnet.netcoredbg.value_converters").simple_unwrap("Value", frame_id, vars, var_path, cb) end,
}
