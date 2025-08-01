local M = {}

function M.is_tuple(className)
  className = vim.trim(className)
  if type(className) ~= "string" then return false end

  return className:match("^System%.Value?Tuple") ~= nil
end

local function format_tuple(values)
  local max_items = 5
  local max_chars = 50

  local preview = {}
  local count = #values

  for i = 1, math.min(count, max_items) do
    local val_str = vim.inspect(values[i]):gsub("\n", ""):gsub("%s+", " ")
    table.insert(preview, val_str)
  end

  local preview_str = "(" .. table.concat(preview, ", ") .. ")"

  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("%)$", ", ...)") end

  return preview_str
end

function M.extract(vars, cb)
  local items = vim.tbl_filter(function(v) return v.name:match("^Item%d+$") end, vars)

  local values = vim.tbl_map(function(v) return v.value end, items)
  cb(values, format_tuple(values))
end

return M
