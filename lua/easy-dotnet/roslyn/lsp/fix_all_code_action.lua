local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local apply_workspace_edit = require("easy-dotnet.roslyn.lsp.apply_workspace_edit")

---@param ctx easy-dotnet.Roslyn.CommandContext
return function(data, ctx)
  local title = data.title
  local options = data.arguments[1].FixAllFlavors
  require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(value) return { display = value, value = value } end, options), function(selected)
    local cleanup = job.register_job({ name = title, on_error_text = title .. " failed", on_success_text = title .. " completed" })
    local client = vim.lsp.get_client_by_id(ctx.client_id)
    if not client then return end
    client:request("codeAction/resolveFixAll", {
      title = data.title,
      data = data.arguments[1],
      scope = selected.value,
    }, function(err, response)
      if err then
        cleanup(false)
        logger.error("Error resolving fix all code action: " .. err.message)
        return
      end

      if not (response and response.edit) then return end
      apply_workspace_edit(response.edit, client)
      cleanup(true)
    end)
  end, title, true, true)
end
