local external_access = require("easy-dotnet.roslyn.lsp.external_access")
local logger = require("easy-dotnet.logger")

local M = {}

local should_rename_file_handler = "EasyDotnet.RoslynLanguageServices.Rename.ShouldRenameFileMessageHandler"

---@param msg string
local function rename_log(msg)
  local timestamp = os.date("%H:%M:%S") .. string.format(".%03d", vim.uv.now() % 1000)
  local formatted = string.format("[easy-dotnet rename %s] %s", timestamp, msg)
  if vim.lsp and vim.lsp.log and vim.lsp.log.debug then
    vim.lsp.log.debug(formatted)
  else
    logger.trace(formatted)
  end
end

---@param client vim.lsp.Client
---@param bufnr integer
---@param decision table
local function rename_file_after_workspace_edit(client, bufnr, decision)
  if not decision or decision.shouldRename ~= true or type(decision.oldUri) ~= "string" or type(decision.newUri) ~= "string" then return end

  local ok_old, old_fname = pcall(vim.uri_to_fname, decision.oldUri)
  local ok_new, new_fname = pcall(vim.uri_to_fname, decision.newUri)
  if not ok_old or not ok_new then
    rename_log("file rename skipped: failed to convert rename URIs")
    return
  end

  local ok_tracking, changetracking = pcall(require, "vim.lsp._changetracking")
  if ok_tracking and changetracking.flush then
    rename_log(string.format("flush changes before file rename client=%s buf=%d old_uri=%s", client.id, bufnr, decision.oldUri))
    changetracking.flush(client, bufnr)
  else
    rename_log("file rename continuing without changetracking flush")
  end

  rename_log(string.format("rename file after workspace edit old=%s new=%s", old_fname, new_fname))
  local ok, rename_err = pcall(vim.lsp.util.rename, old_fname, new_fname, { ignoreIfExists = true })
  if not ok then rename_log("file rename failed: " .. tostring(rename_err)) end
end

local function apply_rename_result_then_file_rename(original_handler, err, result, ctx, client, bufnr, decision)
  original_handler(err, result, ctx)
  rename_file_after_workspace_edit(client, bufnr, decision)
end

---@param client vim.lsp.Client
---@param opts easy-dotnet.LspOpts
function M.install(client, opts)
  if client._easy_dotnet_enhanced_rename_installed then return end
  if opts.enhanced_rename ~= true then return end

  client._easy_dotnet_enhanced_rename_installed = true
  external_access.verify_document_handler(client, should_rename_file_handler)

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
        if err then logger.trace("[easy-dotnet] Roslyn rename failed before enhanced rename dispatch: " .. (type(err) == "table" and (err.message or vim.inspect(err)) or tostring(err))) end
        if not result then logger.trace("[easy-dotnet] Roslyn rename returned no workspace edit") end
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
          logger.trace("[easy-dotnet] Enhanced rename decision dispatch failed: " .. (type(dispatch_err) == "table" and (dispatch_err.message or vim.inspect(dispatch_err)) or tostring(dispatch_err)))
          original_handler(err, result, ctx)
          return
        end

        if not decision then
          logger.trace("[easy-dotnet] Enhanced rename decision unavailable")
          original_handler(err, result, ctx)
          return
        end

        if decision.shouldRename ~= true then
          original_handler(err, result, ctx)
          return
        end

        apply_rename_result_then_file_rename(original_handler, err, result, ctx, self, request_bufnr, decision)
      end)
    end

    return original_request(self, method, params, wrapped_handler, bufnr)
  end
end

return M
