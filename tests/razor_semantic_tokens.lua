-- Run from the repository root: nvim --headless -u NONE -l tests/razor_semantic_tokens.lua
assert(vim.fn.has("nvim-0.12") == 1, "These tests require Neovim 0.12+; legacy behavior is simulated")
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local razor = require("easy-dotnet.razor.roslyn")
local warnings = {}
require("easy-dotnet.logger").warn = function(message) warnings[#warnings + 1] = message end

local function equal(expected, actual) assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual })) end
local function wait_for(predicate) assert(vim.wait(3000, predicate, 10), "Timed out waiting for semantic tokens") end

local base_legend = { tokenTypes = { "class" }, tokenModifiers = { "static" } }
local razor_legend = { tokenTypes = { "class", "razorComponentElement" }, tokenModifiers = { "static", "readonly" } }
local function registration(legend)
  return {
    id = "razor-tokens",
    method = "textDocument/semanticTokens",
    registerOptions = {
      documentSelector = { { language = "aspnetcorerazor" } },
      legend = vim.deepcopy(legend),
      range = true,
      full = false,
    },
  }
end

local function mock_client()
  return {
    id = 9999,
    server_capabilities = { semanticTokensProvider = { legend = vim.deepcopy(base_legend), full = { delta = true } } },
    attached_buffers = {},
    request = function() return "request" end,
    supports_method = function() return true end,
    rpc = { request = function() return "rpc" end },
  }
end

local function test_legends()
  local client = mock_client()
  local request, rpc_request, supports_method = client.request, client.rpc.request, client.supports_method
  razor.suppress_semantic_tokens(client)
  equal(request, client.request)
  equal(rpc_request, client.rpc.request)
  equal(supports_method, client.supports_method)

  local reg = registration(razor_legend)
  razor.update_semantic_token_legend(client, { reg })
  equal(razor_legend, client.server_capabilities.semanticTokensProvider.legend)
  equal({ delta = true }, client.server_capabilities.semanticTokensProvider.full)
  equal(nil, client.server_capabilities.semanticTokensProvider.range)
  reg.registerOptions.legend.tokenTypes[2] = "changed"
  equal(razor_legend, client.server_capabilities.semanticTokensProvider.legend)
  razor.update_semantic_token_legend(client, { registration(razor_legend), registration(base_legend) })
  equal(razor_legend, client.server_capabilities.semanticTokensProvider.legend)

  local incompatible = vim.deepcopy(razor_legend)
  incompatible.tokenTypes[3] = "markupElement"
  incompatible.tokenModifiers[1] = "readonly"
  razor.update_semantic_token_legend(client, { registration(incompatible) })
  equal(razor_legend, client.server_capabilities.semanticTokensProvider.legend)
  equal(true, client._easy_dotnet_razor_semantic_tokens_suppressed)
  equal(1, #warnings)
  razor.update_semantic_token_legend(client, { registration(incompatible) })
  equal(1, #warnings)

  client = mock_client()
  incompatible.tokenTypes[1] = "method"
  razor.update_semantic_token_legend(client, { registration(razor_legend), registration(incompatible) })
  equal(base_legend, client.server_capabilities.semanticTokensProvider.legend)
  equal(2, #warnings)

  client = mock_client()
  client.server_capabilities.semanticTokensProvider = nil
  razor.update_semantic_token_legend(client, { registration(razor_legend) })
  equal(nil, client.server_capabilities.semanticTokensProvider)
end

local function buffer(extension, filetype)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. extension)
  vim.bo[bufnr].filetype = filetype
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Widget", "value" })
  return bufnr
end

local function test_legacy()
  local has, enable = vim.fn.has, vim.lsp.semantic_tokens.enable
  vim.fn.has = function(feature)
    if feature == "nvim-0.12" then return 0 end
    return has(feature)
  end
  local disabled
  vim.lsp.semantic_tokens.enable = function(value, filter) disabled = { value, filter.bufnr } end
  local client = mock_client()
  local razor_buf, cs_buf = buffer(".cshtml", "razor"), buffer(".cs", "cs")
  razor.suppress_semantic_tokens(client)
  local request = client.request
  razor.suppress_semantic_tokens(client)
  equal(request, client.request)
  razor.disable_semantic_tokens(razor_buf, client)
  equal({ false, razor_buf }, disabled)
  razor.update_semantic_token_legend(client, { registration(razor_legend) })
  equal(base_legend, client.server_capabilities.semanticTokensProvider.legend)

  for _, method in ipairs({ "textDocument/semanticTokens/range", "textDocument/semanticTokens/full", "textDocument/semanticTokens/full/delta" }) do
    equal(false, client:supports_method(method, razor_buf))
    equal(true, client:supports_method(method, cs_buf))
    equal("request", client:request(method, { textDocument = { uri = vim.uri_from_bufnr(cs_buf) } }, nil, cs_buf))
    local response
    client:request(method, { textDocument = { uri = vim.uri_from_bufnr(razor_buf) } }, function(_, result) response = result end, razor_buf)
    wait_for(function() return response ~= nil end)
    equal(method:match("/delta$") and { edits = {} } or { data = {} }, response)
  end
  for _, extension in ipairs({ ".razor", ".cshtml" }) do
    local response
    client.rpc.request("textDocument/semanticTokens/range", { textDocument = { uri = vim.uri_from_fname(vim.fn.tempname() .. extension) } }, function(_, result) response = result end)
    wait_for(function() return response ~= nil end)
    equal({ data = {} }, response)
  end
  equal("rpc", client.rpc.request("textDocument/hover", {}))
  vim.fn.has, vim.lsp.semantic_tokens.enable = has, enable
  vim.api.nvim_buf_delete(razor_buf, { force = true })
  vim.api.nvim_buf_delete(cs_buf, { force = true })
end

local function registration_handler(bulk)
  local enable = vim.lsp.enable
  vim.lsp.enable = function() end
  require("easy-dotnet.roslyn.lsp").enable({ log_level = "Information", config = {}, bulk_filewatcher_registrations = bulk })
  vim.lsp.enable = enable
  return vim.lsp.config[require("easy-dotnet.constants").lsp_client_name].handlers["client/registerCapability"]
end

local function test_native(bulk, buffers)
  local razor_buf, cs_buf = unpack(buffers or { buffer(".razor", "razor"), buffer(".cs", "cs") })
  if buffers then vim.api.nvim_buf_set_name(razor_buf, vim.fn.tempname() .. ".cshtml") end
  local cs_uri = vim.uri_from_bufnr(cs_buf)
  vim.api.nvim_set_current_buf(razor_buf)
  local requests, sequence, stopped = {}, 0, false
  local client_id = vim.lsp.start({
    name = "razor-semantic-test",
    capabilities = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), { textDocument = { semanticTokens = { dynamicRegistration = true } } }),
    get_language_id = function(_, ft) return ft == "razor" and "aspnetcorerazor" or "csharp" end,
    on_init = razor.suppress_semantic_tokens,
    on_attach = function(client, bufnr)
      razor.suppress_semantic_tokens(client)
      if vim.bo[bufnr].filetype == "razor" then razor.disable_semantic_tokens(bufnr, client) end
    end,
    handlers = { ["client/registerCapability"] = registration_handler(bulk) },
    cmd = function(dispatchers)
      return {
        request = function(method, params, callback)
          sequence = sequence + 1
          local id = sequence
          requests[#requests + 1] = { method = method, params = params }
          vim.schedule(function()
            if stopped then return end
            local result
            if method == "initialize" then
              result = {
                capabilities = {
                  textDocumentSync = 1,
                  semanticTokensProvider = { legend = vim.deepcopy(base_legend), range = true, full = { delta = true } },
                },
              }
            elseif method == "textDocument/semanticTokens/range" then
              result = { data = params.textDocument.uri == cs_uri and { 0, 0, 6, 0, 1 } or { 0, 0, 6, 1, 2 } }
            elseif method == "textDocument/semanticTokens/full" and params.textDocument.uri == cs_uri then
              result = { data = { 0, 0, 6, 0, 1 }, resultId = "cs-result" }
            elseif method == "textDocument/semanticTokens/full/delta" then
              result = { edits = {}, resultId = "cs-result" }
            end
            callback(nil, result, id)
          end)
          return true, id
        end,
        notify = function() return true end,
        is_closing = function() return stopped end,
        terminate = function()
          stopped = true
          dispatchers.on_exit(0, 0)
        end,
      }
    end,
  })
  local client = assert(vim.lsp.get_client_by_id(assert(client_id)))
  wait_for(function() return client.initialized end)
  local function register(legend) client.handlers["client/registerCapability"](nil, { registrations = { registration(legend) } }, { client_id = client_id }) end
  local function token(bufnr, token_type)
    local tokens = vim.lsp.semantic_tokens.get_at_pos(bufnr, 0, 0)
    return tokens and tokens[1] and tokens[1].type == token_type and tokens[1]
  end
  register(razor_legend)
  wait_for(function() return token(razor_buf, "razorComponentElement") end)
  equal(true, token(razor_buf, "razorComponentElement").modifiers.readonly)
  assert(vim.lsp.buf_attach_client(cs_buf, client_id))
  vim.api.nvim_set_current_buf(cs_buf)
  wait_for(function() return token(cs_buf, "class") end)
  equal(true, token(cs_buf, "class").modifiers.static)
  vim.api.nvim_buf_set_lines(cs_buf, 1, 2, false, { "edited C#" })
  wait_for(function()
    return vim.iter(requests):any(function(request) return request.method == "textDocument/semanticTokens/full/delta" end)
  end)
  vim.api.nvim_set_current_buf(razor_buf)
  register(razor_legend)
  vim.api.nvim_buf_set_lines(razor_buf, 1, 2, false, { "edited" })
  wait_for(function()
    local state = vim.lsp.semantic_tokens.__STHighlighter.active[razor_buf].client_state[client_id]
    return state.current_result.version == vim.lsp.util.buf_versions[razor_buf] and token(razor_buf, "razorComponentElement")
  end)
  local request_count = #requests
  vim.api.nvim_exec_autocmds("WinScrolled", { buffer = razor_buf })
  wait_for(function() return #requests > request_count and token(razor_buf, "razorComponentElement") end)
  equal(razor_legend, client.server_capabilities.semanticTokensProvider.legend)

  local incompatible = { tokenTypes = { "method" }, tokenModifiers = { "static" } }
  register(incompatible)
  wait_for(function()
    local tokens = vim.lsp.semantic_tokens.get_at_pos(razor_buf, 0, 0)
    return not tokens or #tokens == 0
  end)
  equal(false, client:supports_method("textDocument/semanticTokens/range", razor_buf))
  equal(true, client:supports_method("textDocument/semanticTokens/full", cs_buf))
  assert(token(cs_buf, "class"))
  equal(true, vim.lsp.semantic_tokens.is_enabled({ bufnr = razor_buf }))
  assert(vim.iter(requests):any(function(request) return request.method == "textDocument/semanticTokens/range" end))
  client:stop(true)
  wait_for(function() return vim.lsp.get_client_by_id(client_id) == nil end)
  return { razor_buf, cs_buf }
end

local function test_highlights()
  require("easy-dotnet")
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  equal("@type", vim.api.nvim_get_hl(0, { name = "@lsp.type.razorComponentElement.razor", link = true }).link)
  equal("@tag.attribute", vim.api.nvim_get_hl(0, { name = "@lsp.type.markupAttribute.razor", link = true }).link)
  vim.api.nvim_set_hl(0, "@lsp.type.razorComponentElement.razor", { link = "Special" })
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  equal("Special", vim.api.nvim_get_hl(0, { name = "@lsp.type.razorComponentElement.razor", link = true }).link)
  vim.cmd("highlight clear")
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  equal("@type", vim.api.nvim_get_hl(0, { name = "@lsp.type.razorComponentElement.razor", link = true }).link)
end

test_legends()
test_legacy()
local buffers = test_native(false)
test_native(true, buffers)
for _, bufnr in ipairs(buffers) do
  vim.api.nvim_buf_delete(bufnr, { force = true })
end
test_highlights()
equal("", vim.v.errmsg)
print("Razor semantic token tests passed")
