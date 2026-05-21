local logger = require("easy-dotnet.logger")

local M = {}

local function is_razor_buffer(bufnr)
  bufnr = tonumber(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "razor"
end

local function is_razor_uri(uri)
  if type(uri) ~= "string" then return false end

  local ok, filename = pcall(vim.uri_to_fname, uri)
  local path = ok and filename or uri
  return path:match("%.razor$") ~= nil or path:match("%.cshtml$") ~= nil
end

local function is_razor_params(params)
  local uri = vim.tbl_get(params or {}, "textDocument", "uri")
  if type(uri) ~= "string" then return false end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) and vim.uri_from_bufnr(bufnr) == uri then return is_razor_buffer(bufnr) end
  end

  return is_razor_uri(uri)
end

local function is_semantic_tokens_method(method) return type(method) == "string" and method:match("^textDocument/semanticTokens") ~= nil end

local function empty_semantic_tokens_response(method)
  if method == "textDocument/semanticTokens/full/delta" then return { edits = {} } end
  return { data = {} }
end

local function is_duplicate_key_diagnostic_error(err)
  if type(err) ~= "table" then return false end

  local message = err.message or vim.tbl_get(err, "data", "message")
  if type(message) ~= "string" or not message:find("An item with the same key has already been added", 1, true) then return false end

  local stack = vim.tbl_get(err, "data", "stack")
  if type(stack) ~= "string" then return false end
  return stack:find("RemoteDiagnosticsService", 1, true) ~= nil or stack:find("DocumentPullDiagnosticsEndpoint", 1, true) ~= nil
end

function M.disable_semantic_tokens(bufnr, client)
  if not (vim.api.nvim_buf_is_valid(bufnr) and client and client.id) then return end

  if vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.enable then
    vim.lsp.semantic_tokens.enable(false, { bufnr = bufnr })
    return
  end

  if vim.lsp.semantic_tokens and vim.lsp.semantic_tokens.stop then vim.lsp.semantic_tokens.stop(bufnr, client.id) end
end

function M.handle_diagnostic(err, result, ctx, config)
  if err and is_razor_params(ctx and ctx.params) and is_duplicate_key_diagnostic_error(err) then return vim.NIL end

  local handler = vim.lsp.handlers["textDocument/diagnostic"]
  if handler then return handler(err, result, ctx, config) end
  if err then logger.warn("[easy-dotnet] Roslyn diagnostic request failed: " .. (err.message or tostring(err))) end
  return result
end

function M.suppress_semantic_tokens(client)
  if client._easy_dotnet_razor_semantic_tokens_suppressed then return end
  client._easy_dotnet_razor_semantic_tokens_suppressed = true

  local request = client.request
  client.request = function(self, method, params, handler, bufnr)
    if is_semantic_tokens_method(method) and (is_razor_buffer(bufnr) or is_razor_params(params)) then
      local resolved_bufnr = vim._resolve_bufnr(bufnr)
      if handler then
        vim.schedule(
          function()
            handler(nil, empty_semantic_tokens_response(method), {
              method = method,
              client_id = self.id,
              request_id = nil,
              bufnr = resolved_bufnr,
              params = params,
            })
          end
        )
      end
      return true, nil
    end

    return request(self, method, params, handler, bufnr)
  end

  local rpc_request = client.rpc and client.rpc.request
  if rpc_request then
    client.rpc.request = function(method, params, callback, notify_reply_callback)
      if is_semantic_tokens_method(method) and is_razor_params(params) then
        if callback then
          vim.schedule(function()
            callback(nil, empty_semantic_tokens_response(method), nil)
            if notify_reply_callback then notify_reply_callback(nil) end
          end)
        end
        return true, nil
      end

      return rpc_request(method, params, callback, notify_reply_callback)
    end
  end

  local supports_method = client.supports_method
  client.supports_method = function(self, method, bufnr)
    local resolved_bufnr = type(bufnr) == "table" and bufnr.bufnr or bufnr
    if is_semantic_tokens_method(method) and is_razor_buffer(resolved_bufnr) then return false end
    return supports_method(self, method, bufnr)
  end
end

return M
