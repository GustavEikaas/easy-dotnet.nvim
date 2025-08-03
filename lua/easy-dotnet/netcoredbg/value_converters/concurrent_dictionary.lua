local M = {}

function M.is_concurrent_dictionary(class_name)
  class_name = vim.trim(class_name or "")
  if type(class_name) ~= "string" then return false end
  return class_name:match("^System%.Collections%.Concurrent%.ConcurrentDictionary") ~= nil
end

---Extracts key-value pairs from a C# Dictionary
---
---Finds a `_count` entry to limit the number of extracted pairs.
---Returns a Lua table
---If a value is missing, it will be represented as the string `"null"`.
---
---@param vars table[] The top-level fields of the ConcurrentDictionary
---@param cb fun(result: table<string, Variable>, preview: string)
M.extract = function(var_path, vars, cb)
  local tables_ref = nil

  for _, entry in ipairs(vars) do
    if entry.name == "_tables" then
      tables_ref = tonumber(entry.variablesReference)
      break
    end
  end

  if not tables_ref then
    cb({}, "{}")
    return {}
  end

  require("easy-dotnet.netcoredbg").fetch_variables(tables_ref, 1, function(tables_children)
    local buckets_ref = nil

    for _, item in ipairs(tables_children) do
      if item.name == "_buckets" then
        buckets_ref = tonumber(item.variablesReference)
        break
      end
    end

    if not buckets_ref then
      cb({}, "{}")
      return
    end

    require("easy-dotnet.netcoredbg").fetch_variables(buckets_ref, 2, function(bucket_entries)
      local result = {}
      local added = 0

      for _, bucket in ipairs(bucket_entries) do
        if bucket.children then
          for _, node in ipairs(bucket.children) do
            if node.name == "_node" and node.children then
              local key_var, value_var = nil, nil

              for _, kv in ipairs(node.children) do
                if kv.name == "_key" then
                  kv.var_path = var_path .. "._tables._buckets" .. bucket.name .. "." .. node.name .. "." .. kv.name
                  key_var = kv
                elseif kv.name == "_value" then
                  kv.var_path = var_path .. "._tables._buckets" .. bucket.name .. "." .. node.name .. "." .. kv.name
                  value_var = kv
                end
              end

              if key_var then
                added = added + 1
                table.insert(result, {
                  name = added,
                  type = "easy_dotnet_kv_wrapper",
                  variablesReference = 999999,
                  value = "",
                  children = {
                    vim.tbl_extend("force", key_var, { name = "Key" }),
                    vim.tbl_extend("force", value_var, { name = "Value" }),
                  },
                })
                break
              end
            end
          end
        end
      end

      cb(result, require("easy-dotnet.netcoredbg.pretty_printers.kv-pair-list").pretty_print(result))
    end)
  end)

  return {}
end

return M
