local external_access = require("easy-dotnet.roslyn.lsp.external_access")

local M = {}

local handler_name = "EasyDotnet.RoslynLanguageServices.ImportMissingNamespaces.ImportMissingNamespacesMessageHandler"
local command_name = "easy-dotnet.roslyn.importMissingNamespaces"

local function get_existing_using_block(lines)
  local items = {}
  local start_line = nil
  local end_line = nil

  for i, line in ipairs(lines) do
    if line:match("^using%s+[%w%.]+;$") then
      start_line = start_line or (i - 1)
      end_line = i
      table.insert(items, vim.trim(line))
    elseif start_line then
      break
    end
  end

  return items, start_line, end_line
end

local function merge_usings(existing, added)
  local seen = {}
  local merged = {}

  local function add(items)
    for _, line in ipairs(items) do
      line = vim.trim(line)

      if line ~= "" and not seen[line] then
        seen[line] = true
        table.insert(merged, line)
      end
    end
  end

  add(existing)
  add(added)

  table.sort(merged, function(a, b) return a < b end)

  return merged
end

local function apply_using_block(bufnr, new_usings)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local existing, start_line, end_line = get_existing_using_block(lines)
  local merged = merge_usings(existing, new_usings)

  -- Edit buffer lines directly so Neovim manages the file's line endings; building
  -- multi-line text for an LSP edit corrupts CRLF files (mixes \n into a \r\n file).
  if start_line then
    vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, merged)
  else
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, vim.list_extend(merged, { "" }))
  end
end

local function normalize_response(response)
  if type(response) ~= "table" then return nil end

  return {
    canImport = response.canImport or response.CanImport,
    usings = response.usings or response.Usings,
  }
end

local function import_action(usings, bufnr)
  return {
    title = "Import missing namespaces",
    kind = "quickfix",
    edit = {
      changes = {},
    },
    command = {
      title = "Import missing namespaces",
      command = command_name,
      arguments = { { usings = usings, bufnr = bufnr } },
    },
  }
end

local function append_action(result, usings, bufnr)
  local actions = type(result) == "table" and vim.deepcopy(result) or {}
  table.insert(actions, import_action(usings, bufnr))
  return actions
end

function M.install(client)
  if client._easy_dotnet_import_missing_namespaces_installed then return end

  client._easy_dotnet_import_missing_namespaces_installed = true
  external_access.verify_document_handler(client, handler_name)

  local original_request = client.request

  client.request = function(self, method, params, handler, bufnr)
    if method ~= "textDocument/codeAction" or type(params) ~= "table" then return original_request(self, method, params, handler, bufnr) end

    local original_handler = handler or self.handlers[method] or vim.lsp.handlers[method]
    if not original_handler then return original_request(self, method, params, handler, bufnr) end

    local request_bufnr = bufnr or vim.api.nvim_get_current_buf()

    local wrapped_handler = function(err, result, ctx)
      if err then
        original_handler(err, result, ctx)
        return
      end

      -- Namespace resolution is done server-side by the Roslyn language-services
      -- extension, which has full semantic access (metadata + extension methods).
      external_access.dispatch_document(self, request_bufnr, handler_name, vim.empty_dict(), function(dispatch_err, response)
        if dispatch_err then
          original_handler(err, result, ctx)
          return
        end

        response = normalize_response(response)
        if not response or response.canImport ~= true or type(response.usings) ~= "table" or #response.usings == 0 then
          original_handler(err, result, ctx)
          return
        end

        original_handler(err, append_action(result, response.usings, request_bufnr), ctx)
      end)
    end

    return original_request(self, method, params, wrapped_handler, bufnr)
  end
end

function M.import_missing_namespaces(data, ctx)
  local args = data and data.arguments and data.arguments[1]
  if type(args) ~= "table" or type(args.usings) ~= "table" or #args.usings == 0 then return end

  local bufnr = args.bufnr or (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
  apply_using_block(bufnr, args.usings)
end

return M
