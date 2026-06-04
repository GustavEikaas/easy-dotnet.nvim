local external_access = require("easy-dotnet.roslyn.lsp.external_access")
local logger = require("easy-dotnet.logger")

local M = {}

local handler_name = "EasyDotnet.RoslynLanguageServices.CreateType.CreateTypeFromUsageMessageHandler"
local command_name = "easy-dotnet.roslyn.createTypeFromUsage"

local function debug(msg) logger.trace(msg) end

local function normalize_plan(plan)
  if type(plan) ~= "table" then return nil end

  return {
    canCreate = plan.canCreate or plan.CanCreate,
    typeName = plan.typeName or plan.TypeName,
    filePath = plan.filePath or plan.FilePath,
    fileText = plan.fileText or plan.FileText,
    title = plan.title or plan.Title,
    reason = plan.reason or plan.Reason,
  }
end

local function create_type_action(plan)
  return {
    title = plan.title or ("Create class '" .. plan.typeName .. "'"),
    kind = "quickfix",
    edit = {
      changes = {},
    },
    command = {
      title = plan.title or ("Create class '" .. plan.typeName .. "'"),
      command = command_name,
      arguments = { plan },
    },
  }
end

local function append_action(result, plan)
  local actions = type(result) == "table" and vim.deepcopy(result) or {}
  table.insert(actions, create_type_action(plan))
  return actions
end

local function add_position(positions, seen, position)
  if type(position) ~= "table" or type(position.line) ~= "number" or type(position.character) ~= "number" then return end

  local key = position.line .. ":" .. position.character
  if seen[key] then return end

  seen[key] = true
  table.insert(positions, {
    line = position.line,
    character = position.character,
  })
end

local function code_action_positions(params)
  local positions = {}
  local seen = {}

  for _, diagnostic in ipairs(params.context and params.context.diagnostics or {}) do
    add_position(positions, seen, diagnostic.range and diagnostic.range.start)
  end

  add_position(positions, seen, params.range and params.range.start)
  return positions
end

local function dispatch_at_positions(client, bufnr, positions, index, cb)
  local position = positions[index]
  if not position then
    cb(nil, nil)
    return
  end

  debug(string.format("dispatch client=%s buf=%s position=%d:%d", client.id, bufnr, position.line, position.character))
  external_access.dispatch_document(client, bufnr, handler_name, {
    line = position.line,
    character = position.character,
  }, function(dispatch_err, plan)
    if dispatch_err then
      cb(dispatch_err)
      return
    end

    plan = normalize_plan(plan)
    if plan and plan.canCreate == true and type(plan.filePath) == "string" and type(plan.fileText) == "string" then
      debug(string.format("plan accepted type=%s path=%s", tostring(plan.typeName), plan.filePath))
      cb(nil, plan)
      return
    end

    debug("plan rejected: " .. vim.inspect(plan))
    dispatch_at_positions(client, bufnr, positions, index + 1, cb)
  end)
end

function M.install(client, opts)
  if client._easy_dotnet_create_type_from_usage_installed then return end
  if opts.create_type_from_usage ~= true then return end

  client._easy_dotnet_create_type_from_usage_installed = true
  debug("install client=" .. tostring(client.id))
  external_access.verify_document_handler(client, handler_name)

  local original_request = client.request

  client.request = function(self, method, params, handler, bufnr)
    if method ~= "textDocument/codeAction" or type(params) ~= "table" or type(params.range) ~= "table" or type(params.range.start) ~= "table" then
      return original_request(self, method, params, handler, bufnr)
    end

    local original_handler = handler or self.handlers[method] or vim.lsp.handlers[method]
    if not original_handler then return original_request(self, method, params, handler, bufnr) end

    local request_bufnr = bufnr or vim.api.nvim_get_current_buf()
    local positions = code_action_positions(params)
    debug(string.format("codeAction intercepted client=%s buf=%s positions=%d diagnostics=%d", self.id, request_bufnr, #positions, #(params.context and params.context.diagnostics or {})))

    local wrapped_handler = function(err, result, ctx)
      if err then
        original_handler(err, result, ctx)
        return
      end

      dispatch_at_positions(self, request_bufnr, positions, 1, function(dispatch_err, plan)
        if dispatch_err then
          logger.trace("[easy-dotnet] Create type from usage dispatch failed: " .. (type(dispatch_err) == "table" and (dispatch_err.message or vim.inspect(dispatch_err)) or tostring(dispatch_err)))
          original_handler(err, result, ctx)
          return
        end

        if not plan then
          debug("no create-type plan; returning original code actions")
          original_handler(err, result, ctx)
          return
        end

        debug("appending action: " .. tostring(plan.title or plan.typeName))
        original_handler(err, append_action(result, plan), ctx)
      end)
    end

    return original_request(self, method, params, wrapped_handler, bufnr)
  end
end

function M.create_type_from_usage(data, ctx)
  local plan = normalize_plan(data and data.arguments and data.arguments[1])
  if type(plan) ~= "table" or type(plan.filePath) ~= "string" or type(plan.fileText) ~= "string" then return end

  if vim.uv.fs_stat(plan.filePath) then
    vim.notify("[easy-dotnet] File already exists: " .. plan.filePath, vim.log.levels.WARN)
    return
  end

  vim.fn.mkdir(vim.fs.dirname(plan.filePath), "p")
  vim.fn.writefile(vim.split(plan.fileText, "\n", { plain = true }), plan.filePath)

  local client = ctx and ctx.client_id and vim.lsp.get_client_by_id(ctx.client_id)
  if client then client:notify("workspace/didChangeWatchedFiles", {
    changes = {
      { uri = vim.uri_from_fname(plan.filePath), type = 1 },
    },
  }) end

  vim.cmd.edit(vim.fn.fnameescape(plan.filePath))
end

return M
