local M = {}

M.enable_filetypes = function()
  vim.filetype.add({
    filename = {
      ["secrets.json"] = "json5",
      ["launchSettings.json"] = "json5",
      ["appsettings.json"] = "json5",
    },
    pattern = {
      ["appsettings%.%a+%.json"] = "json5",
    },
    extension = {
      props = "xml",
    },
  })
end

return M
