local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local current_solution = require("easy-dotnet.current_solution")

local M = {
  state = {},
  watcher_registered = {},
  pending_watchers = {}, -- Collect all watcher registrations per client
  solution_loaded = {}, -- Track if solution is loaded per client
  solution_state = {},
  checked_buffers = {},
}
local function now() return vim.uv.now() end
function M.start()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if ft == "cs" then vim.api.nvim_exec_autocmds("FileType", {
        buffer = bufnr,
      }) end
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

local function is_file_in_cwd(filepath)
  local cwd = vim.fn.getcwd()

  local abs_file = vim.fs.normalize(vim.fn.fnamemodify(filepath, ":p"))
  local abs_cwd = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))

  if not abs_cwd:match("/$") then abs_cwd = abs_cwd .. "/" end

  return abs_file:sub(1, #abs_cwd) == abs_cwd
end

function M.find_project_or_solution(bufnr, cb)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  if buf_path:match("^%a+://") then return nil end
  if vim.fn.filereadable(buf_path) == 0 then return nil end

  local sln_by_root_dir = current_solution.try_get_selected_solution()
  if sln_by_root_dir and is_file_in_cwd(buf_path) then
    cb(vim.fs.dirname(sln_by_root_dir))
    return
  end

  local project = root_finder.find_csproj_from_file(buf_path)

  if not project then
    cb(vim.fs.dirname(buf_path))
    return
  end

  local sln = root_finder.find_solutions_from_file(project)

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
    current_solution.set_solution(r.display)
    cb(vim.fs.dirname(r.display))
  end, "Pick solution file to start Roslyn from", true, true)
end

function M.find_sln_or_csproj(dir)
  local sln = vim.fs.find(function(name) return name:match("%.slnx?$") end, { path = dir, upward = false, limit = 1 })
  if sln[1] then return sln[1], "sln" end

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
end

local default_roslyn_settings = {
  ["csharp|code_lens"] = {
    dotnet_enable_tests_code_lens = false,
  },
}

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

---@param opts easy-dotnet.LspOpts
function M.enable(opts)
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end
  local cmd = { "dotnet", "easydotnet", "roslyn", "start" }

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

  local cap = vim.tbl_deep_extend("keep", existing_config and existing_config.capabilities or {}, {
    textDocument = {
      codeLens = {
        dynamicRegistration = true,
      },
      diagnostic = {
        dynamicRegistration = true,
      },
    },
    workspace = {
      didChangeWatchedFiles = {
        dynamicRegistration = true,
      },
    },
  })

  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_client_name] = {
    cmd = cmd,
    filetypes = { "cs" },
    root_dir = M.find_project_or_solution,
    capabilities = cap,
    on_init = function(client)
      M.solution_state[client.id] = { loaded_at = nil }
      local file, type = M.find_sln_or_csproj(client.root_dir)
      if not file then return end

      local uri = vim.uri_from_fname(file)
      if type == "sln" then
        M.state[client.id] = job.register_job({ name = "Opening solution", on_error_text = "Failed to open solution", on_success_text = "Workspace ready", timeout = 150000 })
        client:notify("solution/open", { solution = uri })
      elseif type == "csproj" then
        M.state[client.id] = job.register_job({ name = "Opening project", on_error_text = "Failed to open project", on_success_text = "Workspace ready", timeout = 15000 })
        client:notify("project/open", { projects = { uri } })
      else
        logger.warn("Unknown file selected as root_file " .. file)
      end
    end,
    on_exit = function(code, _, client_id)
      M.state[client_id] = nil
      M.watcher_registered[client_id] = nil
      M.pending_watchers[client_id] = nil
      M.solution_loaded[client_id] = nil
      M.solution_state[client_id] = nil
      M.checked_buffers = {}
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
      vim.b[buf].roslyn_buf_opened_at = now()
      if require("easy-dotnet.options").get_option("lsp").auto_refresh_codelens then
        vim.lsp.codelens.refresh()
        vim.api.nvim_create_autocmd({ "BufEnter", "CursorHold", "InsertLeave" }, {
          buffer = buf,
          callback = vim.lsp.codelens.refresh,
        })
      end
      check_project_context(client, buf)
    end,
    commands = {
      ["roslyn.client.fixAllCodeAction"] = require("easy-dotnet.roslyn.lsp.fix_all_code_action"),
      ["roslyn.client.nestedCodeAction"] = require("easy-dotnet.roslyn.lsp.nested_code_action"),
      ["roslyn.client.completionComplexEdit"] = require("easy-dotnet.roslyn.lsp.complex_edit"),
      ["roslyn.client.peekReferences"] = require("easy-dotnet.roslyn.lsp.peek_references"),
      -- ["dotnet.test.run"] = require("easy-dotnet.roslyn.lsp.test_run"),
    },
    handlers = {
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
      ["workspace/projectInitializationComplete"] = function(_, _, ctx, _)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not client then return end
        if M.solution_state[client.id] then M.solution_state[client.id].loaded_at = now() end
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
    },
    settings = settings,
  }

  vim.lsp.enable(constants.lsp_client_name)
end

return M
