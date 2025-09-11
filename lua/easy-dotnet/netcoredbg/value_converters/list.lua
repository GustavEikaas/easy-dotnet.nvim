local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end

---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.Collections%.Generic%.List") ~= nil
  end,
  extract = function(_, vars, var_path, _, cb)
    local max_count = 0
    local var_ref = nil

    for _, entry in ipairs(vars) do
      if entry.name == "_size" and tonumber(entry.value) then
        ---@diagnostic disable-next-line: cast-local-type
        max_count = tonumber(entry.value)
      elseif entry.name == "_items" then
        var_ref = tonumber(entry.variablesReference)
      end
    end

    if var_ref then
      local result = {}
      local added = 0
      ---@param r Variable[]
      require("easy-dotnet.netcoredbg").fetch_variables(var_ref, 0, function(r)
        table.sort(r, function(a, b)
          local a_index = index_to_number(a.name)
          local b_index = index_to_number(b.name)
          return a_index < b_index
        end)

        for _, children_ref in ipairs(r) do
          children_ref.var_path = var_path .. "._items" .. children_ref.name
          if added >= max_count then break end
          table.insert(result, children_ref)
          added = added + 1
        end

        cb(result, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
      end)
    end
  end,
}
