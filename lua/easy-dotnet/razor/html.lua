local constants = require("easy-dotnet.constants")
local logger = require("easy-dotnet.logger")

local M = {
  clients = {},
  documents = {},
  warned = {},
  roslyn_roots = {},
}

local virtual_suffix = "__virtual.html"
local virtual_scheme = "razor-html"
local log_file = vim.fs.joinpath(vim.fn.stdpath("state"), "easy-dotnet", "razor.log")

local forwarded_methods = {
  "textDocument/codeAction",
  "textDocument/colorPresentation",
  "textDocument/completion",
  "textDocument/definition",
  "textDocument/documentColor",
  "textDocument/documentHighlight",
  "textDocument/documentSymbol",
  "textDocument/foldingRange",
  "textDocument/formatting",
  "textDocument/hover",
  "textDocument/implementation",
  "textDocument/onTypeFormatting",
  "textDocument/rangeFormatting",
  "textDocument/references",
  "textDocument/signatureHelp",
}

local nil_forwarded_responses = {
  ["textDocument/hover"] = true,
  ["textDocument/signatureHelp"] = true,
}

local function empty_forwarded_response(method)
  if nil_forwarded_responses[method] then return vim.NIL end
  return {}
end

local function get_opts()
  local lsp = require("easy-dotnet.options").get_option("lsp") or {}
  return ((lsp.razor or {}).html or {})
end

local function is_enabled()
  local lsp = require("easy-dotnet.options").get_option("lsp") or {}
  local razor = lsp.razor or {}
  local html = razor.html or {}
  return razor.enabled ~= false and html.enabled ~= false
end

local function warn_once(key, message)
  if M.warned[key] then return end
  M.warned[key] = true
  logger.warn(message)
end

local function append_log(message)
  if type(message) ~= "string" or message == "" then return end
  vim.fn.mkdir(vim.fs.dirname(log_file), "p")
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  vim.fn.writefile({ string.format("%s %s", timestamp, message) }, log_file, "a")
end

local function command_available(cmd)
  if type(cmd) == "function" then return true end
  if type(cmd) ~= "table" or type(cmd[1]) ~= "string" or cmd[1] == "" then return false end
  return vim.fn.executable(cmd[1]) == 1
end

local function default_cmd(dispatchers, config)
  local cmd = "vscode-html-language-server"
  if config and config.root_dir then
    local local_cmd = vim.fs.joinpath(config.root_dir, "node_modules/.bin", cmd)
    if vim.fn.executable(local_cmd) == 1 then cmd = local_cmd end
  end
  return vim.lsp.rpc.start({ cmd, "--stdio" }, dispatchers)
end

local function html_settings()
  return {
    html = {
      format = {
        enable = true,
      },
    },
    css = {
      validate = true,
    },
    javascript = {
      validate = true,
    },
  }
end

local function ensure_client(root_dir)
  if not is_enabled() then return nil end
  root_dir = root_dir or vim.fn.getcwd()

  local existing = M.clients[root_dir]
  if existing and not existing:is_stopped() then return existing end

  local opts = get_opts()
  local cmd = opts.cmd or default_cmd
  if not command_available(cmd) then
    local executable = type(cmd) == "table" and cmd[1] or "vscode-html-language-server"
    warn_once("missing-html-lsp", "[easy-dotnet] Razor HTML support requires `" .. executable .. "` in PATH")
    return nil
  end

  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.textDocument.completion.completionItem.snippetSupport = true

  local client_id = vim.lsp.start({
    name = constants.lsp_html_client_name,
    cmd = cmd,
    root_dir = root_dir,
    filetypes = { "html", "razor" },
    get_language_id = function() return "html" end,
    capabilities = capabilities,
    settings = html_settings(),
    init_options = {
      embeddedLanguages = {
        css = true,
        javascript = true,
      },
      provideFormatter = true,
      configurationSection = { "html", "css", "javascript" },
    },
  }, { attach = false })

  if not client_id then
    warn_once("html-lsp-start", "[easy-dotnet] Failed to start Razor HTML language server")
    return nil
  end

  local client = vim.lsp.get_client_by_id(client_id)
  if not client then return nil end
  M.clients[root_dir] = client
  return client
end

local function wait_until_initialized(client, timeout)
  if client.initialized then return true end
  vim.wait(timeout or 5000, function() return client.initialized or client:is_stopped() end, 10)
  return client.initialized == true
end

local function to_virtual_uri(uri)
  local ok, parsed = pcall(vim.uri_to_fname, uri)
  if ok and parsed and parsed ~= "" then return virtual_scheme .. "://" .. parsed .. virtual_suffix end
  return uri:gsub("^file://", virtual_scheme .. "://") .. virtual_suffix
end

local function normalize_text(text)
  if type(text) ~= "string" then return "" end
  return text:gsub("\r\n", "\n")
end

local function get_document(uri)
  if not uri then return nil end
  return M.documents[uri]
end

local function open_or_update_document(root_dir, razor_uri, checksum, text)
  local client = ensure_client(root_dir)
  if not client then return nil end

  text = normalize_text(text)
  local doc = M.documents[razor_uri]
  if not wait_until_initialized(client, get_opts().request_timeout or 5000) then return nil end
  if not doc then
    doc = {
      uri = to_virtual_uri(razor_uri),
      root_dir = root_dir,
      version = 0,
      checksum = checksum,
      text = text,
    }
    M.documents[razor_uri] = doc
    client:notify("textDocument/didOpen", {
      textDocument = {
        uri = doc.uri,
        languageId = "html",
        version = doc.version,
        text = doc.text,
      },
    })
    return doc
  end

  doc.version = doc.version + 1
  doc.checksum = checksum
  doc.text = text
  client:notify("textDocument/didChange", {
    textDocument = {
      uri = doc.uri,
      version = doc.version,
    },
    contentChanges = {
      {
        text = doc.text,
      },
    },
  })
  return doc
end

local function close_document(root_dir, razor_uri)
  local doc = M.documents[razor_uri]
  if not doc then return end
  M.documents[razor_uri] = nil

  local client = M.clients[root_dir]
  if not client or client:is_stopped() then return end
  client:notify("textDocument/didClose", {
    textDocument = {
      uri = doc.uri,
    },
  })
end

local function rewrite_text_document(value, uri)
  if type(value) ~= "table" then return end
  if type(value.textDocument) == "table" then value.textDocument.uri = uri end
end

local function forwarded_request(method)
  return function(err, params, ctx, config)
    if not (params and params.textDocument and params.textDocument.uri and params.checksum and params.request) then
      local handler = vim.lsp.handlers[ctx.method]
      if handler then return handler(err, params, ctx, config) end
      return nil
    end

    if not is_enabled() then return empty_forwarded_response(method) end

    local roslyn = vim.lsp.get_client_by_id(ctx.client_id)
    local root_dir = roslyn and roslyn.root_dir or vim.fn.getcwd()
    local client = ensure_client(root_dir)
    if not client then return empty_forwarded_response(method) end
    if not wait_until_initialized(client, get_opts().request_timeout or 5000) then return empty_forwarded_response(method) end

    local razor_uri = params and params.textDocument and params.textDocument.uri
    local doc = get_document(razor_uri)
    if not doc then return empty_forwarded_response(method) end
    if params.checksum and doc.checksum and params.checksum ~= doc.checksum then return empty_forwarded_response(method) end

    local request = vim.deepcopy(params.request or {})
    rewrite_text_document(request, doc.uri)

    local timeout = get_opts().request_timeout or 5000
    local response = client:request_sync(method, request, timeout)
    if not response or response.err or response.result == nil then return empty_forwarded_response(method) end
    return response.result
  end
end

function M.attach(client)
  M.roslyn_roots[client.id] = client.root_dir
  ensure_client(client.root_dir)
end

function M.handle_update_html(_, params, ctx)
  if not is_enabled() then return vim.NIL end
  if not params or not params.textDocument or not params.textDocument.uri then return vim.NIL end

  local roslyn = vim.lsp.get_client_by_id(ctx.client_id)
  local root_dir = roslyn and roslyn.root_dir or vim.fn.getcwd()
  if roslyn then M.roslyn_roots[roslyn.id] = root_dir end

  open_or_update_document(root_dir, params.textDocument.uri, params.checksum, params.text)
  return vim.NIL
end

function M.register_razor_close(client, buf)
  M.roslyn_roots[client.id] = client.root_dir
  M.attach(client)

  local group = vim.api.nvim_create_augroup(string.format("easy-dotnet-razor-close-%d-%d", client.id, buf), { clear = true })
  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = buf,
    once = true,
    callback = function()
      local uri = vim.uri_from_bufnr(buf)
      close_document(client.root_dir, uri)
      client:request("razor/documentClosed", { uri = uri }, function() end, buf)
    end,
  })
end

function M.stop_for_roslyn_client(client_id)
  local root_dir = M.roslyn_roots[client_id]
  M.roslyn_roots[client_id] = nil
  if not root_dir then return end

  for razor_uri, doc in pairs(M.documents) do
    if doc.root_dir == root_dir then close_document(root_dir, razor_uri) end
  end

  local client = M.clients[root_dir]
  M.clients[root_dir] = nil
  if client and not client:is_stopped() then client:stop(true) end
end

function M.handlers()
  local handlers = {
    ["razor/updateHtml"] = M.handle_update_html,
    ["razor/log"] = function(_, params)
      if params and params.message then append_log("[razor] " .. params.message) end
      return vim.NIL
    end,
  }

  for _, method in ipairs(forwarded_methods) do
    handlers[method] = forwarded_request(method)
  end

  return handlers
end

function M.log_file() return log_file end

return M
