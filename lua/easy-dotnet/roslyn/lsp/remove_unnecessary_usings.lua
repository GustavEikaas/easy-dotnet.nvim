local logger = require("easy-dotnet.logger")
local constants = require("easy-dotnet.constants")
local apply_workspace_edit = require("easy-dotnet.roslyn.lsp.apply_workspace_edit")

return function()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = constants.lsp_client_name })[1]
  if not client then
    logger.error("Roslyn is not attached to the current buffer")
    return
  end

  local action = {
    title = "Remove unnecessary usings",
    kind = "quickfix",
    data = {
      CustomTags = { "RemoveUnnecessaryImports" },
      TextDocument = { uri = vim.uri_from_bufnr(bufnr) },
      CodeActionPath = { "Remove unnecessary usings" },
      Range = {
        ["start"] = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
      UniqueIdentifier = "Remove unnecessary usings",
    },
  }

  client:request("codeAction/resolve", action, function(err, resolved)
    if err then
      logger.error("Failed to remove unnecessary usings: " .. err.message)
      return
    end
    apply_workspace_edit(resolved and resolved.edit, client)
  end, bufnr)
end
