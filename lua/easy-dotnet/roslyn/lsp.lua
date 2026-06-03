local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local current_solution = require("easy-dotnet.current_solution")
local razor_html = require("easy-dotnet.razor.html")
local razor_roslyn = require("easy-dotnet.razor.roslyn")
local git_branch_watcher = require("easy-dotnet.roslyn.lsp.git_branch_watcher")

local M = {
  state = {},
  watcher_registered = {},
  pending_watchers = {}, -- Collect all watcher registrations per client
  solution_loaded = {}, -- Track if solution is loaded per client
  solution_state = {},
  checked_buffers = {},
}

local function is_roslyn_filetype(ft) return ft == "cs" or ft == "razor" end

local function is_buffer_in_root(bufnr, root_dir)
  if not root_dir then return true end

  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or name:match("^%a+://") then return false end

  local root = vim.fs.normalize(vim.fn.fnamemodify(root_dir, ":p"))
  local path = vim.fs.normalize(vim.fn.fnamemodify(name, ":p"))
  if path == root then return true end

  if not root:match("[/\\]$") then root = root .. "/" end
  return path:sub(1, #root) == root
end

---@param root_dir string|nil
function M.start(root_dir)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if is_roslyn_filetype(ft) and vim.bo[bufnr].buftype == "" and is_buffer_in_root(bufnr, root_dir) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.api.nvim_exec_autocmds("FileType", {
            buffer = bufnr,
          })
        end)
      end
    end
  end
end

function M.stop()
  local bufnr = vim.api.nvim_get_current_buf()
  local attached_clients = vim.lsp.get_clients({ bufnr = bufnr, name = constants.lsp_client_name })
  for _, client in ipairs(attached_clients) do
    client:stop(true)
  end
end

function M.restart()
  M.stop()
  M.start()
end

local function restart_root(root_dir)
  logger.info("[easy-dotnet] Git branch changed; restarting Roslyn")
  pcall(vim.cmd, "checktime")

  for _, client in ipairs(vim.lsp.get_clients({ name = constants.lsp_client_name })) do
    if client.root_dir == root_dir then client:stop(true) end
  end

  vim.defer_fn(function() M.start(root_dir) end, 250)
end

---@param client vim.lsp.Client
---@param bufnr number
---@return boolean
local function does_file_belong_to_active_client(client, bufnr)
  local params = {
    _vs_textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  }
  local response = client:request_sync("textDocument/_vs_getProjectContexts", params, 1000, bufnr)
  if not response or response.err then
    local err_msg = response and response.err and (response.err.message or "Timeout or No Response")
    logger.warn("Roslyn failed to resolve project context: " .. err_msg)
    return false
  end

  if not response.result or not response.result._vs_projectContexts then return false end

  local default_idx = response.result._vs_defaultIndex or 1
  local context = response.result._vs_projectContexts[default_idx + 1]

  if not context then return false end

  local is_misc = context._vs_is_miscellaneous

  return not is_misc
end

local function check_project_context(client, bufnr)
  local solution_ts = M.solution_state[client.id] and M.solution_state[client.id].loaded_at
  if not solution_ts then return end

  local buf_opened_at = vim.b[bufnr].roslyn_buf_opened_at or 0
  if buf_opened_at < solution_ts then return end

  if M.checked_buffers[bufnr] == "valid" then return end

  local params = {
    _vs_textDocument = { uri = vim.uri_from_bufnr(bufnr) },
  }

  local function query_server(is_retry)
    client:request("textDocument/_vs_getProjectContexts", params, function(err, result)
      if err then
        logger.error(vim.inspect(err))
        return
      end
      if not result or not result._vs_projectContexts then return end

      local default_idx = result._vs_defaultIndex or 1
      local context = result._vs_projectContexts[default_idx + 1]

      if not context then return end

      local is_misc = context._vs_is_miscellaneous

      if not is_misc then
        M.checked_buffers[bufnr] = "valid"
      elseif is_misc and not is_retry then
        local uri = vim.uri_from_bufnr(bufnr)
        client:notify("workspace/didChangeWatchedFiles", {
          changes = {
            { uri = uri, type = 1 },
          },
        })

        vim.defer_fn(function()
          if vim.api.nvim_buf_is_valid(bufnr) then query_server(true) end
        end, 1000)
      elseif is_misc and is_retry then
        logger.warn("Active file is not part of the workspace. IntelliSense may be limited.")
        M.checked_buffers[bufnr] = "misc"
      end
    end, bufnr)
  end

  query_server(false)
end

local function has_client_for_root_dir(root_dir) return vim.lsp.get_clients({ root_dir = root_dir })[1] end

local function has_roslyn_client_for_root(root_dir) return vim.lsp.get_clients({ name = constants.lsp_client_name, root_dir = root_dir })[1] ~= nil end

local function is_file_in_cwd(filepath)
  local cwd = vim.fn.getcwd()

  local abs_file = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
  local abs_cwd = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))

  if not abs_cwd:match("/$") then abs_cwd = abs_cwd .. "/" end

  return abs_file:sub(1, #abs_cwd) == abs_cwd
end

function M.find_project_or_solution(bufnr, cb)
  coroutine.wrap(function()
    local buf_path = vim.api.nvim_buf_get_name(bufnr)
    if buf_path:match("^%a+://") then return nil end
    if vim.fn.filereadable(buf_path) == 0 then return nil end

    local sln_by_root_dir = current_solution.try_get_selected_solution()
    if sln_by_root_dir then
      if is_file_in_cwd(buf_path) then
        cb(vim.fs.dirname(sln_by_root_dir))
        return
      else
        local existing_client = has_client_for_root_dir(vim.fs.dirname(sln_by_root_dir))
        if existing_client and does_file_belong_to_active_client(existing_client, bufnr) then
          cb(vim.fs.dirname(sln_by_root_dir))
          return
        end
      end
    end

    local co = coroutine.running()
    local function await(fn)
      local result
      fn(function(r)
        result = r
        coroutine.resume(co)
      end)
      coroutine.yield()
      return result
    end

    local project = await(function(done) root_finder.find_csproj_from_file(buf_path, done) end)

    if not project then
      cb(vim.fs.dirname(buf_path))
      return
    end

    local sln = await(function(done) root_finder.find_solutions_from_file(project, done) end)

    if vim.tbl_isempty(sln) then
      cb(vim.fs.dirname(project))
      return
    end

    local sln_default = sln_parse.try_get_selected_solution_file()
    local selected_sln

    if sln_default then
      local sln_basename = vim.fs.basename(sln_default)
      for _, s in ipairs(sln) do
        if vim.fs.basename(s) == sln_basename then
          selected_sln = s
          break
        end
      end
    end

    if selected_sln then
      cb(vim.fs.dirname(selected_sln))
      return
    end

    require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(value) return { display = value } end, sln), function(r)
      cb(vim.fs.dirname(r.display))

      local existing_sln = sln_parse.try_get_selected_solution_file()
      -- GH#771
      if existing_sln then
        local possible_client = vim.lsp.get_clients({ root_dir = vim.fs.dirname(existing_sln) })
        if possible_client then return end
      end
      current_solution.set_solution(r.display)
    end, "Pick solution file to start Roslyn from", true, true)
  end)()
end

function M.find_sln_or_csproj(dir)
  local slns = vim.tbl_map(function(val) return vim.fs.normalize(val) end, vim.fs.find(function(name) return name:match("%.slnx?$") end, { path = dir, upward = false, limit = 100 }))

  if #slns > 0 then
    local possible_sln = sln_parse.try_get_selected_solution_file()
    if possible_sln and vim.tbl_contains(slns, vim.fs.normalize(possible_sln)) then
      return possible_sln, "sln"
    else
      return slns[1], "sln"
    end
  end

  local csproj = vim.fs.find(function(name) return name:match("%.csproj$") end, { path = dir, upward = false, limit = 1 })
  if csproj[1] then return csproj[1], "csproj" end

  return nil
end

---Register all collected registrations in bulk
---@param client vim.lsp.Client
function M.register_watchers_bulk(client)
  local client_id = client.id
  local pending = M.pending_watchers[client_id]
  if not pending or #pending == 0 then return end

  client:_register(pending)

  M.pending_watchers[client_id] = nil
end

local default_roslyn_settings = {
  ["csharp|code_lens"] = {
    dotnet_enable_tests_code_lens = false,
  },
  razor = {
    language_server = {
      cohosting_enabled = true,
    },
  },
}

---@param msg string
local function rename_log(msg)
  local timestamp = os.date("%H:%M:%S") .. string.format(".%03d", vim.uv.now() % 1000)
  local formatted = string.format("[easy-dotnet rename %s] %s", timestamp, msg)
  if vim.lsp and vim.lsp.log and vim.lsp.log.debug then
    vim.lsp.log.debug(formatted)
  else
    logger.debug(formatted)
  end
end

---@param client vim.lsp.Client
local function refresh_diag(client)
  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  local open_doc = client.server_capabilities and client.attached_buffers and client.attached_buffers[bufnr]
  if not open_doc then return end

  local params = {
    textDocument = {
      uri = vim.uri_from_bufnr(bufnr),
      version = vim.lsp.util.buf_versions[bufnr] or 0,
    },
    contentChanges = {},
  }

  client:notify("textDocument/didChange", params)
  rename_log(string.format("refresh_diag sent didChange client=%s buf=%d uri=%s", client.id, bufnr, params.textDocument.uri))
end

---@param client vim.lsp.Client
---@param buf integer
local function register_file_rename_tracking(client, buf)
  local group = vim.api.nvim_create_augroup(string.format("easy-dotnet-roslyn-rename-%d-%d", client.id, buf), { clear = true })

  vim.api.nvim_create_autocmd("BufFilePre", {
    group = group,
    buffer = buf,
    callback = function()
      vim.b[buf].easy_dotnet_old_name = vim.api.nvim_buf_get_name(buf)
      rename_log(string.format("BufFilePre client=%s buf=%d old_name=%s", client.id, buf, vim.b[buf].easy_dotnet_old_name or ""))
    end,
  })

  vim.api.nvim_create_autocmd("BufFilePost", {
    group = group,
    buffer = buf,
    callback = function()
      local old_name = vim.b[buf].easy_dotnet_old_name
      vim.b[buf].easy_dotnet_old_name = nil

      local new_name = vim.api.nvim_buf_get_name(buf)
      if not old_name or old_name == "" or new_name == "" or old_name == new_name then return end
      rename_log(string.format("BufFilePost client=%s buf=%d old_name=%s new_name=%s", client.id, buf, old_name, new_name))

      client:notify("workspace/didRenameFiles", {
        files = {
          {
            oldUri = vim.uri_from_fname(old_name),
            newUri = vim.uri_from_fname(new_name),
          },
        },
      })

      client:notify("workspace/didChangeWatchedFiles", {
        changes = {
          { uri = vim.uri_from_fname(old_name), type = 3 },
          { uri = vim.uri_from_fname(new_name), type = 1 },
        },
      })
    end,
  })
end

---@param opts easy-dotnet.LspOpts
function M.preload_roslyn(opts)
  local sln = current_solution.try_get_selected_solution()
  if sln and opts.preload_roslyn == true then
    local dirname = vim.fs.dirname(sln)
    local cap = vim.tbl_deep_extend("force", vim.lsp.config[constants.lsp_client_name], {
      root_dir = dirname,
    })
    vim.lsp.start(cap)
  end
end

---@param client vim.lsp.Client
local function populate_source_generated_buffer(client, buf, file)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local params = {
    resultId = vim.b[buf].resultId,
    textDocument = {
      uri = file,
    },
  }

  local function handler(err, result)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    if not result or type(result) ~= "table" then return end
    if result.resultId == vim.b[buf].resultId then return end
    assert(not err, vim.inspect(err))
    local text = result.text
    if text == vim.NIL or type(text) ~= "string" then text = "" end
    text = text:gsub("\r\n", "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
    vim.b[buf].resultId = result.resultId
    vim.lsp.buf_attach_client(buf, client.id)
    vim.bo[buf].filetype = "cs"
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end

  local response = client:request_sync("sourceGeneratedDocument/_roslyn_getText", params, 2000, buf)
  if not response or response.err then
    local err_msg = response and response.err and response.err.message or "Timeout or No Response"
    logger.warn("Roslyn generation failed: " .. err_msg)
    return
  end
  handler(response.err, response.result)
end

local function source_generated_autocmd()
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = "roslyn-source-generated://*",
    callback = function(args)
      vim.bo[args.buf].modifiable = true
      vim.bo[args.buf].swapfile = false

      local clients = vim.lsp.get_clients({ name = constants.lsp_client_name })

      for _, client in ipairs(clients) do
        if does_file_belong_to_active_client(client, args.buf) then populate_source_generated_buffer(client, args.buf, args.file) end
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
    pattern = "roslyn-source-generated://*",
    callback = function(args)
      local name = args.file:match("/([^/]+)%?") or ""
      vim.api.nvim_set_option_value("winbar", "󰑕 " .. name .. "  [source generated]", { win = 0 })
    end,
  })
end

local function use_roslyn_fold(bufnr)
  local enabled = require("easy-dotnet.options").get_option("lsp").set_fold_expr
  if not enabled then return end
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win][0].foldmethod = "expr"
    vim.wo[win][0].foldexpr = "v:lua.vim.lsp.foldexpr()"
  end
end

local function fix_indent_expression(buf)
  if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].indentexpr = "GetCSIndent(v:lnum)" end
end

local function mark_lsp_created_files(params)
  local edit = params and params.edit
  local document_changes = edit and edit.documentChanges
  if type(document_changes) ~= "table" then return end

  local lsp_created_files = require("easy-dotnet.roslyn.lsp-created-files")
  for _, change in ipairs(document_changes) do
    if change.kind == "create" or change.type == 1 then lsp_created_files.mark_uri(change.uri) end
  end
end

---@param opts easy-dotnet.LspOpts
function M.enable(opts)
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end
  source_generated_autocmd()
  local cmd = { "dotnet-easydotnet", "roslyn", "start" }
  local razor_enabled = not opts.razor or opts.razor.enabled ~= false
  table.insert(cmd, "--clientProcessId")
  table.insert(cmd, tostring(vim.fn.getpid()))

  if opts.roslynator_enabled then table.insert(cmd, "--roslynator") end
  if opts.easy_dotnet_analyzer_enabled then table.insert(cmd, "--easy-dotnet-analyzer") end

  if opts.analyzer_assemblies then
    for _, dll in ipairs(opts.analyzer_assemblies) do
      table.insert(cmd, "--analyzer")
      table.insert(cmd, dll)
    end
  end
  local existing_config = vim.lsp.config[constants.lsp_client_name]

  local settings = vim.tbl_deep_extend("force", default_roslyn_settings, opts.config.settings or {}, existing_config and existing_config.settings or {})

  local cap = vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), existing_config and existing_config.capabilities or {}, {
    textDocument = {
      codeAction = {
        dynamicRegistration = true,
      },
      codeLens = {
        dynamicRegistration = true,
      },
      colorProvider = {
        dynamicRegistration = true,
      },
      completion = {
        dynamicRegistration = true,
      },
      definition = {
        dynamicRegistration = true,
      },
      diagnostic = {
        dynamicRegistration = true,
      },
      documentHighlight = {
        dynamicRegistration = true,
      },
      documentSymbol = {
        dynamicRegistration = true,
      },
      foldingRange = {
        dynamicRegistration = true,
        lineFoldingOnly = true,
      },
      formatting = {
        dynamicRegistration = true,
      },
      hover = {
        dynamicRegistration = true,
      },
      implementation = {
        dynamicRegistration = true,
      },
      rangeFormatting = {
        dynamicRegistration = true,
      },
      references = {
        dynamicRegistration = true,
      },
      rename = {
        dynamicRegistration = true,
      },
      semanticTokens = {
        dynamicRegistration = true,
      },
      signatureHelp = {
        dynamicRegistration = true,
      },
      synchronization = {
        dynamicRegistration = true,
      },
    },
    workspace = {
      didChangeWatchedFiles = {
        dynamicRegistration = true,
      },
      fileOperations = {
        didRename = true,
        willRename = true,
      },
      workspaceEdit = {
        documentChanges = true,
        resourceOperations = { "create", "rename", "delete" },
      },
    },
  })

  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_client_name] = {
    cmd = cmd,
    cmd_env = {
      --TODO: use this for when server allows changing configuration
      -- Configuration = "Release",
    },
    filetypes = razor_enabled and { "cs", "razor" } or { "cs" },
    get_language_id = function(_, filetype)
      if filetype == "cs" then return "csharp" end
      if filetype == "razor" then return "aspnetcorerazor" end
      return filetype
    end,
    root_dir = M.find_project_or_solution,
    capabilities = cap,
    on_init = function(client)
      git_branch_watcher.register(client, opts, restart_root)
      require("easy-dotnet.roslyn.lsp.enhanced_rename").install(client, opts)
      require("easy-dotnet.roslyn.lsp.create_type_from_usage").install(client, opts)
      razor_roslyn.suppress_semantic_tokens(client)
      M.solution_state[client.id] = { loaded_at = nil }
      local file, type = M.find_sln_or_csproj(client.root_dir)
      if not file then return end

      local uri = vim.uri_from_fname(file)
      if type == "sln" then
        M.state[client.id] =
          job.register_job({ name = "[roslyn] Loading solution", on_error_text = "[roslyn] Failed to open solution", on_success_text = "[roslyn] Workspace ready", timeout = 150000 })
        client:notify("solution/open", { solution = uri })
      elseif type == "csproj" then
        M.state[client.id] = job.register_job({ name = "[roslyn] Loading project", on_error_text = "[roslyn] Failed to open project", on_success_text = "[roslyn] Workspace ready", timeout = 15000 })
        client:notify("project/open", { projects = { uri } })
      else
        logger.warn("Unknown file selected as root_file " .. file)
      end
    end,
    on_exit = function(code, _, client_id)
      razor_html.stop_for_roslyn_client(client_id)
      M.state[client_id] = nil
      M.watcher_registered[client_id] = nil
      M.pending_watchers[client_id] = nil
      M.solution_loaded[client_id] = nil
      M.solution_state[client_id] = nil
      M.checked_buffers = {}
      git_branch_watcher.unregister_client(client_id, has_roslyn_client_for_root)
      vim.schedule(function()
        if code == 0 or code == 143 then
          logger.info("[easy-dotnet] Roslyn stopped")
          return
        end

        if code == 75 then
          logger.error("[easy-dotnet]: Roslyn requires dotnet 10 sdk installed")
        else
          logger.error("[easy-dotnet] Roslyn crashed")
        end
      end)
    end,
    on_attach = function(client, buf)
      razor_roslyn.suppress_semantic_tokens(client)
      vim.b[buf].roslyn_buf_opened_at = vim.uv.now()
      vim.b[buf].easy_dotnet_roslyn_open_uri = vim.uri_from_bufnr(buf)
      register_file_rename_tracking(client, buf)
      if vim.bo[buf].filetype == "cs" then
        use_roslyn_fold(buf)
        fix_indent_expression(buf)
      elseif vim.bo[buf].filetype == "razor" then
        razor_html.register_razor_close(client, buf)
        razor_roslyn.disable_semantic_tokens(buf, client)
        vim.schedule(function() razor_roslyn.disable_semantic_tokens(buf, client) end)
      end
      if vim.bo[buf].filetype == "cs" and require("easy-dotnet.options").get_option("lsp").auto_refresh_codelens then
        if vim.fn.has("nvim-0.12") == 1 then
          vim.lsp.codelens.enable(true, { bufnr = buf })
          vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
            buffer = buf,
            callback = function() vim.lsp.codelens.enable(true, { bufnr = buf }) end,
          })
        else
          vim.lsp.codelens.refresh()
          vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
            buffer = buf,
            callback = vim.lsp.codelens.refresh,
          })
        end
      end
      check_project_context(client, buf)
    end,
    commands = {
      ["roslyn.client.fixAllCodeAction"] = require("easy-dotnet.roslyn.lsp.fix_all_code_action"),
      ["roslyn.client.nestedCodeAction"] = require("easy-dotnet.roslyn.lsp.nested_code_action"),
      ["roslyn.client.completionComplexEdit"] = require("easy-dotnet.roslyn.lsp.complex_edit"),
      ["roslyn.client.peekReferences"] = require("easy-dotnet.roslyn.lsp.peek_references"),
      ["easy-dotnet.roslyn.createTypeFromUsage"] = require("easy-dotnet.roslyn.lsp.create_type_from_usage").create_type_from_usage,
      -- ["dotnet.test.run"] = require("easy-dotnet.roslyn.lsp.test_run"),
    },
    handlers = vim.tbl_deep_extend("force", razor_enabled and razor_html.handlers() or {}, {
      ["textDocument/diagnostic"] = razor_roslyn.handle_diagnostic,
      ["client/registerCapability"] = function(err, params, ctx, config)
        local client_id = ctx.client_id
        if params.registrations then
          for _, registration in ipairs(params.registrations) do
            if registration.method == "workspace/didChangeWatchedFiles" and registration.registerOptions and registration.registerOptions.watchers then
              -- Filter out watchers for non-existing paths
              registration.registerOptions.watchers = vim
                .iter(registration.registerOptions.watchers)
                :filter(function(watch)
                  if type(watch.globPattern) == "table" and watch.globPattern.baseUri then return vim.loop.fs_stat(vim.uri_to_fname(watch.globPattern.baseUri)) ~= nil end
                  return true -- Keep watchers without baseUri (string patterns)
                end)
                :totable()

              -- If solution is already loaded, let registration through normally
              if not M.solution_loaded[client_id] then
                -- Cache the entire registration (will register in bulk on solution/open)
                if not M.pending_watchers[client_id] then M.pending_watchers[client_id] = {} end
                table.insert(M.pending_watchers[client_id], registration)
                -- Block the registration
                registration.registerOptions.watchers = {}
              end
            end
          end
        end
        return vim.lsp.handlers["client/registerCapability"](err, params, ctx, config)
      end,
      ["workspace/applyEdit"] = function(err, params, ctx, config)
        mark_lsp_created_files(params)
        return vim.lsp.handlers["workspace/applyEdit"](err, params, ctx, config)
      end,
      ["workspace/projectInitializationComplete"] = function(_, _, ctx, _)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not client then return end
        if M.solution_state[client.id] then M.solution_state[client.id].loaded_at = vim.uv.now() end
        local workspace_job = M.state[client.id]
        if workspace_job and type(workspace_job) == "function" then
          vim.defer_fn(function()
            workspace_job(true)
            M.state[client.id] = nil
            -- Register all collected watchers in bulk after solution/project is ready
            M.register_watchers_bulk(client)
            -- Mark solution as loaded - future registrations will go through normally
            M.solution_loaded[client.id] = true
          end, 2000)
        end
        vim.defer_fn(function() refresh_diag(client) end, 500)
      end,
      ["workspace/refreshSourceGeneratedDocument"] = function(_, _, ctx)
        local client = assert(vim.lsp.get_client_by_id(ctx.client_id))

        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) then
            local ok, uri = pcall(vim.api.nvim_buf_get_name, buf)
            if ok and uri:match("^roslyn%-source%-generated://") then populate_source_generated_buffer(client, buf, uri) end
          end
        end
      end,
    }),
    settings = settings,
  }

  vim.lsp.enable(constants.lsp_client_name)
end

return M
