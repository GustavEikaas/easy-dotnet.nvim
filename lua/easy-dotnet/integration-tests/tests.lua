local helpers = require("easy-dotnet.integration-tests.helpers")
local M = {}

M.dotnet_build_telescope = {
  handle = function()
    vim.cmd("silent! Dotnet build")
    local function telescope_prompt_focused() return vim.bo.filetype == "TelescopePrompt" end
    if helpers.wait_interval(telescope_prompt_focused, { timeout = 5000, interval = 100 }) then
      vim.defer_fn(function() vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true) end, 500)
      vim.notify("[PASS] TelescopePrompt buffer is focused after :Dotnet build")
      return true
    else
      print("[FAIL] TelescopePrompt buffer did NOT appear after :Dotnet build")
      return false
    end
  end,
}

return M
