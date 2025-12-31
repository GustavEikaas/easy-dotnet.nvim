---@type easy-dotnet.Debugger.ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    return class_name:match("^System%.Value?Tuple") ~= nil
  end,
  extract = function(_, vars, var_path, _, cb)
    local items = vim
      .iter(vars)
      :filter(function(v) return v.name:match("^Item%d+$") end)
      :map(function(item)
        return vim.tbl_extend("force", item, {
          var_path = var_path .. "." .. item.name,
        })
      end)
      :totable()

    cb(items, require("easy-dotnet.netcoredbg.pretty_printers.tuple").pretty_print(items))
  end,
}
