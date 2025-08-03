local M = {}

--- Returns true if the class name matches ReadOnlyCollection<T>
---@param class_name string
---@return boolean
M.is_readonly_list = function(class_name) return type(class_name) == "string" and class_name:match("^System%.Collections%.ObjectModel%.ReadOnlyCollection") ~= nil end

--- Extracts values from a ReadOnlyCollection<T>
--- It simply extracts the `_list` field and passes it to the existing `list` extractor
---@param vars table
---@param cb function
function M.extract(var_path, vars, cb)
  for _, entry in ipairs(vars) do
    if entry.name == "list" and entry.variablesReference and entry.variablesReference ~= 0 then
      require("easy-dotnet.netcoredbg").fetch_variables(
        entry.variablesReference,
        1,
        function(children) require("easy-dotnet.netcoredbg.value_converters.list").extract(var_path .. ".list", children, cb) end
      )
      return
    end
  end
end

return M
