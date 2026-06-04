local M = {}

M.add_project_reference = function(curr_project_path, cb) return require("easy-dotnet.csproj-mappings").add_project_reference(curr_project_path, cb) end

local function attach_mappings()
  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    pattern = "*.fsproj",
    callback = function(args)
      vim.keymap.set("n", "<leader>ar", function() M.add_project_reference(args.file) end, { buffer = args.buf, silent = true, noremap = true, desc = "Add project reference" })
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
