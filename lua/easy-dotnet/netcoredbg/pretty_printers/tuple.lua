local M = {}

---@param vars Variable[]
M.pretty_print = function(vars)
  local max_items = 5
  local max_chars = 50

  local preview = {}
  local count = #vars

  for i = 1, math.min(count, max_items) do
    local val_str = vim.inspect(vars[i].value):gsub("\n", ""):gsub("%s+", " ")
    table.insert(preview, val_str)
  end

  local preview_str = "(" .. table.concat(preview, ", ") .. ")"

  if count > max_items or #preview_str > max_chars then preview_str = preview_str:gsub("%)$", ", ...)") end

  return preview_str
end

return M
