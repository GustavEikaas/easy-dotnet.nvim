local lsp_helper = require("easy-dotnet.roslyn.create_lsp_notification")
local M = {}

---Open solution
---@param client vim.lsp.Client
---@param solution_path string
function M.solution_open(client, solution_path)
  return lsp_helper.create_lsp_notification({
    client = client,
    method = "solution/open",
    params = {
      solution = vim.uri_from_fname(solution_path),
    },
  })()
end

return M
