local external_access = require("easy-dotnet.roslyn.lsp.external_access")
local logger = require("easy-dotnet.logger")

local M = {}

local should_rename_file_handler = "EasyDotnet.RoslynLanguageServices.Rename.ShouldRenameFileMessageHandler"

local function has_rename_file_operation(document_changes, old_uri, new_uri)
  for _, change in ipairs(document_changes) do
    if change.kind == "rename" and change.oldUri == old_uri and change.newUri == new_uri then return true end
  end
  return false
end

local function ensure_document_changes(edit)
  if edit.documentChanges then return edit.documentChanges end

  edit.documentChanges = {}
  if edit.changes then
    for uri, edits in pairs(edit.changes) do
      table.insert(edit.documentChanges, {
        textDocument = {
          uri = uri,
        },
        edits = edits,
      })
    end
    edit.changes = nil
  end

  return edit.documentChanges
end

local function with_file_rename(edit, decision)
  if not decision or decision.shouldRename ~= true or type(decision.oldUri) ~= "string" or type(decision.newUri) ~= "string" then return edit end

  local result = vim.deepcopy(edit)
  local document_changes = ensure_document_changes(result)
  if has_rename_file_operation(document_changes, decision.oldUri, decision.newUri) then return result end

  logger.debug("[easy-dotnet] Adding file rename to workspace edit: " .. decision.oldUri .. " -> " .. decision.newUri)
  table.insert(document_changes, {
    kind = "rename",
    oldUri = decision.oldUri,
    newUri = decision.newUri,
    options = {
      ignoreIfExists = true,
    },
  })

  return result
end

---@param client vim.lsp.Client
---@param opts easy-dotnet.LspOpts
function M.install(client, opts)
  if client._easy_dotnet_enhanced_rename_installed then return end
  if opts.enhanced_rename == false or opts.easy_dotnet_analyzer_enabled == false then return end

  client._easy_dotnet_enhanced_rename_installed = true

  local original_request = client.request

  client.request = function(self, method, params, handler, bufnr)
    if method ~= "textDocument/rename" or type(params) ~= "table" or type(params.newName) ~= "string" or type(params.position) ~= "table" then
      return original_request(self, method, params, handler, bufnr)
    end

    local original_handler = handler or self.handlers[method] or vim.lsp.handlers[method]
    if not original_handler then return original_request(self, method, params, handler, bufnr) end

    local request_bufnr = bufnr or vim.api.nvim_get_current_buf()
    local wrapped_handler = function(err, result, ctx)
      if err or not result then
        if err then
          logger.debug("[easy-dotnet] Roslyn rename failed before enhanced rename dispatch: " .. (type(err) == "table" and (err.message or vim.inspect(err)) or tostring(err)))
        end
        if not result then logger.debug("[easy-dotnet] Roslyn rename returned no workspace edit") end
        original_handler(err, result, ctx)
        return
      end

      external_access.dispatch_document(self, request_bufnr, should_rename_file_handler, {
        uri = params.textDocument and params.textDocument.uri or vim.uri_from_bufnr(request_bufnr),
        line = params.position.line,
        character = params.position.character,
        newName = params.newName,
      }, function(dispatch_err, decision)
        if dispatch_err then
          logger.debug("[easy-dotnet] Enhanced rename decision dispatch failed: " .. (type(dispatch_err) == "table" and (dispatch_err.message or vim.inspect(dispatch_err)) or tostring(dispatch_err)))
          original_handler(err, result, ctx)
          return
        end

        if not decision then
          logger.debug("[easy-dotnet] Enhanced rename decision unavailable")
          original_handler(err, result, ctx)
          return
        end

        if decision.shouldRename ~= true then
          original_handler(err, result, ctx)
          return
        end

        original_handler(err, with_file_rename(result, decision), ctx)
      end)
    end

    return original_request(self, method, params, wrapped_handler, bufnr)
  end
end

return M
