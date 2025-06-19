local M = {}

local function is_buffer_empty(buf)
  for i = 1, vim.api.nvim_buf_line_count(buf), 1 do
    local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
    if line ~= "" and line ~= nil then return false end
  end

  return true
end

---@alias BootstrapNamespaceMode "file_scoped" | "block_scoped"

---@param mode BootstrapNamespaceMode
local function auto_bootstrap_namespace(bufnr, mode)
  local curr_file = vim.api.nvim_buf_get_name(bufnr)

  if not is_buffer_empty(bufnr) then return end

  local file_name = vim.fn.fnamemodify(curr_file, ":t:r")

  local is_interface = file_name:sub(1, 1) == "I" and file_name:sub(2, 2):match("%u")
  local type_keyword = is_interface and "Interface" or "Class"

  local ns = require("easy-dotnet.constants").ns_id

  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
    virt_text = { { "⏳ Bootstrapping... (do not modify file)", "Comment" } },
    virt_text_pos = "eol",
  })

  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client:roslyn_bootstrap_file(curr_file, type_keyword, mode == "file_scoped", function()
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      vim.cmd("checktime")
    end)
  end)
end

---@param mode BootstrapNamespaceMode
M.auto_bootstrap_namespace = function(mode)
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    pattern = "*.cs",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      auto_bootstrap_namespace(bufnr, mode)
    end,
  })
end

M.add_test_signs = function()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.cs",
    callback = function() require("easy-dotnet.test-signs").add_gutter_test_signs() end,
  })
end

return M
