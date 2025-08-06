---@type ValueConverter
return {
  satisfies_type = function(class_name)
    class_name = vim.trim(class_name)
    if type(class_name) ~= "string" then return false end
    return class_name:match("^System%.Uri$") ~= nil
  end,
  extract = function(_, vars, _, _, cb)
    for _, value in ipairs(vars) do
      if value.name == "_string" then cb({ value = value }, value.value) end
    end
  end,
}
