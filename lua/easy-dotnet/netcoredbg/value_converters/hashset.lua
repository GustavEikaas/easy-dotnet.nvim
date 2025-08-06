local index_to_number = function(r) return tonumber(r:match("%[(%d+)%]")) or 0 end
---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name or "")
    return type(class_name) == "string" and class_name:match("^System%.Collections%.Generic%.HashSet") ~= nil
  end,
  extract = function(_, vars, var_path, _, cb)
    local entries = nil
    local count = 0

    for _, entry in ipairs(vars) do
      if entry.name == "_entries" then
        entries = tonumber(entry.variablesReference)
      elseif entry.name == "_count" then
        count = tonumber(entry.value) or 0
      end
    end

    if not entries or count == 0 then
      cb({}, "{}")
      return
    end

    require("easy-dotnet.netcoredbg").fetch_variables(entries, 1, function(slot_entries)
      table.sort(slot_entries, function(a, b) return index_to_number(a.name) < index_to_number(b.name) end)

      local i = 0
      local result = vim
        .iter(slot_entries)
        :slice(1, count)
        :map(function(r)
          return vim.iter(r.children):find(function(child) return child.name == "Value" end)
        end)
        :map(function(item)
          i = i + 1
          return vim.tbl_extend("force", item, {
            var_path = string.format("%s._entries[%d].%s", var_path, i - 1, item.name),
          })
        end)
        :totable()

      cb(result, require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(result))
    end)
  end,
}
