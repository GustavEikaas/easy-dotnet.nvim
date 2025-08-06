---@type ValueConverter
return {
  satisfies_type = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyCollection") ~= nil end,
  extract = function(frame_id, vars, var_path, _, cb)
    for _, entry in ipairs(vars) do
      if entry.name == "list" and entry.variablesReference and entry.variablesReference ~= 0 then
        require("easy-dotnet.netcoredbg").fetch_variables(
          entry.variablesReference,
          1,
          function(children) require("easy-dotnet.netcoredbg.value_converters.list").extract(frame_id, children, var_path .. ".list", entry.type, cb) end
        )
        return
      end
    end
  end,
}
