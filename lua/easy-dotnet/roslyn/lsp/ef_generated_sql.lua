local external_access = require("easy-dotnet.roslyn.lsp.external_access")

local M = {}

local handler_name = "EasyDotnet.RoslynLanguageServices.EfQuery.DetectEfQueryMessageHandler"
local command_name = "easy-dotnet.roslyn.efGeneratedSql"
local action_title = "View generated SQL (EF Core)"

local function normalize(detection)
  if type(detection) ~= "table" then return nil end

  return {
    found = detection.found or detection.Found,
    line = detection.line or detection.Line,
    character = detection.character or detection.Character,
  }
end

--- The detect handler returns the query expression's own position, so the
--- command invokes the SQL endpoint with a position guaranteed to hit the
--- query, regardless of where the cursor was when the menu opened.
local function sql_action(file_path, detection)
  return {
    title = action_title,
    kind = "quickfix",
    edit = { changes = {} },
    command = {
      title = action_title,
      command = command_name,
      arguments = { { filePath = file_path, line = detection.line, character = detection.character } },
    },
  }
end

function M.install(client, opts)
  if client._easy_dotnet_ef_generated_sql_installed then return end
  if opts.ef_generated_sql ~= true then return end

  client._easy_dotnet_ef_generated_sql_installed = true
  external_access.verify_document_handler(client, handler_name)

  local original_request = client.request

  client.request = function(self, method, params, handler, bufnr)
    if method ~= "textDocument/codeAction" or type(params) ~= "table" or type(params.range) ~= "table" or type(params.range.start) ~= "table" then
      return original_request(self, method, params, handler, bufnr)
    end

    local original_handler = handler or self.handlers[method] or vim.lsp.handlers[method]
    if not original_handler then return original_request(self, method, params, handler, bufnr) end

    local request_bufnr = bufnr or vim.api.nvim_get_current_buf()
    local position = params.range.start

    local wrapped_handler = function(err, result, ctx)
      if err then
        original_handler(err, result, ctx)
        return
      end

      external_access.dispatch_document(self, request_bufnr, handler_name, {
        line = position.line,
        character = position.character,
      }, function(dispatch_err, detection)
        detection = dispatch_err == nil and normalize(detection) or nil

        if not (detection and detection.found == true and type(detection.line) == "number" and type(detection.character) == "number") then
          original_handler(err, result, ctx)
          return
        end

        local actions = type(result) == "table" and vim.deepcopy(result) or {}
        table.insert(actions, sql_action(vim.api.nvim_buf_get_name(request_bufnr), detection))
        original_handler(err, actions, ctx)
      end)
    end

    return original_request(self, method, params, wrapped_handler, bufnr)
  end
end

function M.ef_generated_sql(data)
  local args = data and data.arguments and data.arguments[1]
  if type(args) ~= "table" or type(args.filePath) ~= "string" or type(args.line) ~= "number" or type(args.character) ~= "number" then return end

  require("easy-dotnet.ef-sql-preview").show(args.filePath, args.line, args.character)
end

return M
