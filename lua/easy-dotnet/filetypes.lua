local M = {}

-- TODO: figure out how to properly create autocmd once and apply filetype to buffer once
M.enable_filetypes = function()
  if vim.b.did_ftplugin then
    return
  end

  vim.b.did_ftplugin = true

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.props",
    group = vim.api.nvim_create_augroup("solution_props", { clear = true }),
    callback = function()
      vim.bo.filetype = "xml"
    end,
  })
end

return M
