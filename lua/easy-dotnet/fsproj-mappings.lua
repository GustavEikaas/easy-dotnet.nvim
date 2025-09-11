local M = {}

M.add_project_reference = function(curr_project_path, cb) return require("easy-dotnet.csproj-mappings").add_project_reference(curr_project_path, cb) end

local function attach_mappings()
  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    pattern = "*.fsproj",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_project_path = vim.api.nvim_buf_get_name(bufnr)
      vim.keymap.set("n", "<leader>ar", function()
        coroutine.wrap(function()
          M.add_project_reference(curr_project_path)
        end)()
      end, { buffer = bufnr })
    end,
  })
end

M.package_completion_cmp = {
  complete = require("easy-dotnet.csproj-mappings").package_completion_cmp.complete,

  get_metadata = function(_)
    return {
      priority = 1000,
      filetypes = { "xml", "fsproj" },
    }
  end,
}

M.attach_mappings = attach_mappings

return M
