local M = {}

---@param value any
---@return string
local function sanitize_value(value) return vim.inspect(value):gsub("\n", ""):gsub("%s+", " ") end

local function is_list(tbl) return type(tbl) == "table" and tbl[1] ~= nil end

---@param data table
---@return string
M.pretty_print = function(data)
  local max_elements = 5
  local max_chars = 50

  if is_list(data) then
    return require("easy-dotnet.netcoredbg.pretty_printers.list").pretty_print(data)
  else
    local entries = {}
    local count = 0
    for k, v in pairs(data) do
      if count >= max_elements then
        table.insert(entries, "...")
        break
      end

      local val_str = v
      if type(v) == "table" then
        val_str = v.value
      elseif type(v) ~= "string" then
        val_str = sanitize_value(v)
      end

      table.insert(entries, string.format("%s: %s", k, val_str))
      count = count + 1
    end

    local preview = "{" .. table.concat(entries, ", ") .. "}"
    if #preview > max_chars then preview = preview:gsub("}$", ", ...}") end

    return preview
  end
end

return M
