local M = {}

M.is_readonly_dictionary = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyDictionary") end

function M.extract(vars, cb)
  for _, entry in ipairs(vars) do
    if entry.name == "Dictionary" and entry.variablesReference ~= 0 then
      require("easy-dotnet.netcoredbg").fetch_variables(
        entry.variablesReference,
        1,
        function(children) return require("easy-dotnet.netcoredbg.value_converters.dictionaries").extract(children, cb) end
      )
    end
  end
end

return M
