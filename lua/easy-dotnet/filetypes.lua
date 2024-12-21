local M = {}

-- TODO: figure out how to properly create autocmd once and apply filetype to buffer once
M.enable_filetypes = function()
  vim.filetype.add({
    extension = {
      props = "xml",
    },
  })
end

return M
