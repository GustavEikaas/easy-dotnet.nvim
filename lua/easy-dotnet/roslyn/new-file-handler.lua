local M = {}

local function is_buffer_empty(buf)
  for i = 0, vim.api.nvim_buf_line_count(buf) - 1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line ~= nil and line ~= "" then return false end
  end
  return true
end

function M.register_new_file(client, bufnr)
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not vim.startswith(vim.fs.normalize(curr_file), vim.fs.normalize(vim.fn.getcwd())) then return end
  if not is_buffer_empty(bufnr) then return end

  client:notify("workspace/didChangeWatchedFiles", {
    changes = {
      {
        uri = vim.uri_from_fname(curr_file),
        type = 1,
      },
    },
  })
end

return M
