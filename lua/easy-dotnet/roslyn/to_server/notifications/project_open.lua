local lsp_helper = require("easy-dotnet.roslyn.create_lsp_notification")
local M = {}

---Opens a list of projects
---@param client vim.lsp.Client
---@param project_paths string[]
function M.projects_open(client, project_paths)
  local to_uri = vim.tbl_map(function(path) return vim.uri_from_fname(path) end, project_paths)
  return lsp_helper.create_lsp_notification({
    client = client,
    method = "project/open",
    params = {
      projects = to_uri,
    },
  })()
end

return M
