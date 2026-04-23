local M = {}
local logger = require("easy-dotnet.logger")
local file_utils = require("easy-dotnet.file-utils")

---@param test_file_path string
---@param method_stub string
---@return boolean
function M.append_method_to_test_file(test_file_path, method_stub)
  local lines = vim.fn.readfile(test_file_path)

  local insert_at = nil
  for i = #lines, 1, -1 do
    if lines[i]:match("^}%s*$") then
      insert_at = i
      break
    end
  end

  if not insert_at then
    logger.error("generate-test: could not find closing brace in test file")
    return false
  end

  local stub_lines = vim.split(method_stub, "\n")
  for j = #stub_lines, 1, -1 do
    table.insert(lines, insert_at, stub_lines[j])
  end

  vim.fn.writefile(lines, test_file_path)
  return true
end

---@param test_file_path string
---@param content string
function M.write_test_file(test_file_path, content)
  vim.fn.mkdir(vim.fs.dirname(test_file_path), "p")
  file_utils.overwrite_file(test_file_path, content)
end

---@param file_path string
---@param test_name string
function M.open_and_place_cursor_on_assert(file_path, test_name)
  vim.cmd("edit " .. vim.fn.fnameescape(file_path))
  local in_target_method = false
  for i, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(test_name, 1, true) then in_target_method = true end
    if in_target_method and line:find("// Assert", 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, 8 })
      break
    end
  end
end

return M
