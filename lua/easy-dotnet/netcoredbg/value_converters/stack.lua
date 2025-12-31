local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name or "")
    return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.Stack") ~= nil
  end,
  extract = function(_, vars, var_path, _, cb)
    local array_ref = nil
    local size = 0

    for _, entry in ipairs(vars) do
      if entry.name == "_array" then
        array_ref = tonumber(entry.variablesReference)
      elseif entry.name == "_size" then
        size = tonumber(entry.value) or 0
      end
    end

    if not array_ref or size == 0 then
      cb({}, "[]")
      return
    end

    require("easy-dotnet.netcoredbg").fetch_variables(array_ref, 0, function(children)
      table.sort(children, function(a, b) return index_to_number(a.name) < index_to_number(b.name) end)

      local result = vim.iter(children):slice(1, size):totable()

      table.sort(result, function(a, b) return index_to_number(a.name) > index_to_number(b.name) end)

      local items = vim
        .iter(result)
        :map(function(item)
          return vim.tbl_extend("force", item, {
            var_path = var_path .. "._array" .. item.name,
          })
        end)
        :totable()

      cb(items, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
    end)
  end,
}
