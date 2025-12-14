local logger = require("easy-dotnet.logger")
local constants = require("easy-dotnet.constants")

local M = {
  state = {},
}

function M.enable()
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end
  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_projx_client_name] = {
    cmd = { "dotnet", "easydotnet", "projx-language-server" },
    filetypes = { "xml" },
    root_dir = function(buf_nr, cb)
      local buf_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf_nr))
      local root_dir = vim.fs.dirname(buf_path)
      cb(root_dir)
    end,
    on_exit = function(code)
      vim.schedule(function()
        if code ~= 0 and code ~= 143 then
          vim.notify("[easy-dotnet] ProjX crashed", vim.log.levels.ERROR)
          return
        end
        vim.notify("[easy-dotnet] ProjX stopped", vim.log.levels.INFO)
      end)
    end,
  }

  vim.lsp.enable(constants.lsp_projx_client_name)
end

return M
