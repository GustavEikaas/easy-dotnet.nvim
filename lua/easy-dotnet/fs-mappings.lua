local M = {}

M.add_test_signs = function()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.fs",
    callback = function() require("easy-dotnet.test-signs").add_gutter_test_signs() end,
  })
end

return M
