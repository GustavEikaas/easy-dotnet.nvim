---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyCollection") ~= nil end,
  extract = function(frame_id, vars, var_path, _, cb) require("easy-dotnet.netcoredbg.value_converters").simple_unwrap("list", frame_id, vars, var_path, cb) end,
}
