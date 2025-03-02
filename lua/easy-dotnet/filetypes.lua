local M = {}

M.enable_filetypes = function()
  vim.filetype.add({
    extension = {
      props = "xml",
    },
  })
end

return M
