local logger = require("easy-dotnet.logger")
local constants = require("easy-dotnet.constants")

local M = {}

M.command_name = "easy-dotnet.importMissingNamespaces"

local diagnostics_for_code_action = {
  CS0246 = true, -- type or namespace could not be found
  CS0234 = true, -- type or namespace name does not exist in the namespace
  CS0103 = true, -- name does not exist in the current context
  CS1061 = true, -- no definition / no accessible extension method
}

-- We're omitting CS0103 cause it might give false positives due to ambiguity
-- only later check whether there is available code action
local diagnostics_for_initial_check = {
  CS0246 = true, -- type or namespace could not be found
  CS0234 = true, -- type or namespace name does not exist in the namespace
  CS1061 = true, -- no definition / no accessible extension method
}

local using_pattern = "^using%s+([%w_%.]+);$"

local function get_roslyn_client(bufnr) return vim.lsp.get_clients({ bufnr = bufnr, name = constants.lsp_client_name })[1] end

local function get_target_diagnostics(bufnr)
  local result = {}
  local seen_message = {}

  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    local code = tostring(d.code)

    if diagnostics_for_code_action[code] and not seen_message[d.message] then
      seen_message[d.message] = true
      table.insert(result, d)
    end
  end

  return result
end

local function get_existing_using_block(lines)
  local items = {}
  local start_line = nil
  local end_line = nil

  for i, line in ipairs(lines) do
    if line:match(using_pattern) then
      start_line = start_line or (i - 1)
      end_line = i
      table.insert(items, vim.trim(line))
    elseif start_line then
      break
    end
  end

  return items, start_line, end_line
end

local function is_system_namespace(ns) return ns == "System" or vim.startswith(ns, "System.") end

local function compare_usings(a, b)
  local ns_a, ns_b = a:match(using_pattern), b:match(using_pattern)
  local system_a, system_b = is_system_namespace(ns_a), is_system_namespace(ns_b)
  if system_a ~= system_b then return system_a end
  return ns_a < ns_b
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

  table.sort(merged, compare_usings)

  return merged
end

local function apply_using_block(bufnr, new_usings)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local existing, start_line, end_line = get_existing_using_block(lines)
  local merged = merge_usings(existing, new_usings)

  if not start_line then
    table.insert(merged, "")
    start_line = 0
    end_line = 0
  end

  vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, merged)
end

local function request_actions_for_diag(bufnr, client, diag, cb)
  ---@type lsp.Diagnostic
  local lsp_diag = vim.lsp.diagnostic.from({ diag })[1]

  ---@type lsp.CodeActionParams
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    range = lsp_diag.range,
    context = {
      diagnostics = { lsp_diag },
      only = { "quickfix" },
      triggerKind = vim.lsp.protocol.CodeActionTriggerKind.Invoked,
    },
  }

  local sent = client:request("textDocument/codeAction", params, function(err, actions)
    if err or not actions then
      cb({})
      return
    end

    local result = {}

    for _, action in ipairs(actions) do
      local title = action.title
      if title and title:match(using_pattern) then table.insert(result, title) end
    end

    local has_multiple_potential_namespaces = #result > 1
    if has_multiple_potential_namespaces then
      cb({})
      return
    end

    cb(result)
  end, bufnr)

  if not sent then cb({}) end
end

local function has_multiple_missing_import_diagnostic(bufnr)
  local count = 0
  local seen_location = {}
  local seen_message = {}

  for _, d in ipairs(vim.diagnostic.get(bufnr)) do
    local code = tostring(d.code)
    local diag_location = string.format("%d:%d", d.lnum, d.col)
    if diagnostics_for_initial_check[code] and not seen_location[diag_location] and not seen_message[d.message] then
      count = count + 1
      if count > 1 then return true end
    end
    seen_location[diag_location] = true
    seen_message[d.message] = true
  end

  return false
end

function M.run(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local client = get_roslyn_client(bufnr)
  if not client then
    logger.warn("Roslyn client not found")
    return
  end

  local diagnostics = get_target_diagnostics(bufnr)

  if #diagnostics == 0 then
    logger.trace("No missing imports found")
    return
  end

  local pending = #diagnostics
  local collected = {}

  local function finish()
    pending = pending - 1

    if pending > 0 then return end

    if #collected == 0 then
      logger.info("No unambiguous namespaces to import")
      return
    end

    if vim.api.nvim_buf_is_valid(bufnr) then apply_using_block(bufnr, collected) end
  end

  for _, diag in ipairs(diagnostics) do
    request_actions_for_diag(bufnr, client, diag, function(lines)
      for _, line in ipairs(lines) do
        table.insert(collected, line)
      end

      finish()
    end)
  end
end

function M.register_action(params, callback)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)

  if not has_multiple_missing_import_diagnostic(bufnr) then
    callback(nil, {})
    return
  end

  callback(nil, {
    {
      title = "Import missing namespaces",
      kind = "quickfix",
      command = {
        title = "Import missing namespaces",
        command = M.command_name,
        arguments = { bufnr },
      },
    },
  })
end

return M
