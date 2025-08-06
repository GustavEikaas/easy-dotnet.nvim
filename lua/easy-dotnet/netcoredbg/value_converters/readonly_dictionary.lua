---@type ValueConverter
return {
  satisfies_type = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyDictionary") end,
  extract = function(frame_id, vars, var_path, _, cb)
    for _, entry in ipairs(vars) do
      if entry.name == "Dictionary" and entry.variablesReference ~= 0 then
        require("easy-dotnet.netcoredbg").fetch_variables(
          entry.variablesReference,
          1,
          function(children) return require("easy-dotnet.netcoredbg.value_converters.dictionaries").extract(frame_id, children, var_path .. ".Dictionary", entry.type, cb) end
        )
      end
    end
  end,
}
