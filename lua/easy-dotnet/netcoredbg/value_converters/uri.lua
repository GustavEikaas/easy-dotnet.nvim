---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.Uri$") ~= nil
  end,
  extract = function(frame_id, vars, var_path, _, cb) require("easy-dotnet.netcoredbg.value_converters").simple_unwrap("_string", frame_id, vars, var_path, cb) end,
}
