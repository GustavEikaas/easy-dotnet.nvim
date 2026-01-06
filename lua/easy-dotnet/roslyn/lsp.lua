local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")

local M = {
  state = {},
  watcher_registered = {},
  pending_watchers = {}, -- Collect all watcher registrations per client
  solution_loaded = {}, -- Track if solution is loaded per client
}

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

function M.find_project_or_solution(bufnr, cb)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  if buf_path:match("^%a+://") then return nil end
  if vim.fn.filereadable(buf_path) == 0 then return nil end

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
    require("easy-dotnet.default-manager").set_default_solution(nil, r.display)
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

---@param opts easy-dotnet.LspOpts
function M.enable(opts)
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end
  local cmd = { "dotnet", "easydotnet", "roslyn", "start" }

  if opts.roslynator_enabled then table.insert(cmd, "--roslynator") end

  if opts.analyzer_assemblies then
    for _, dll in ipairs(opts.analyzer_assemblies) do
      table.insert(cmd, "--analyzer")
      table.insert(cmd, dll)
    end
  end

  local existing_config = vim.lsp.config[constants.lsp_client_name]
  local cap = vim.tbl_deep_extend(
    "keep",
    existing_config and existing_config.capabilities or {},
    { textDocument = {
      diagnostic = {
        dynamicRegistration = true,
      },
    }, workspace = {
      didChangeWatchedFiles = {
        dynamicRegistration = true,
      },
    } }
  )

  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_client_name] = {
    cmd = cmd,
    filetypes = { "cs" },
    root_dir = M.find_project_or_solution,
    capabilities = cap,
    on_init = function(client)
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
    on_attach = function(client, buf) require("easy-dotnet.roslyn.new-file-handler").register_new_file(client, buf) end,
    commands = {
      ["roslyn.client.fixAllCodeAction"] = require("easy-dotnet.roslyn.lsp.fix_all_code_action"),
      ["roslyn.client.nestedCodeAction"] = require("easy-dotnet.roslyn.lsp.nested_code_action"),
      ["roslyn.client.completionComplexEdit"] = require("easy-dotnet.roslyn.lsp.complex_edit"),
      -- ["roslyn.client.peekReferences"] = require("easy-dotnet.roslyn.lsp.peek_references"),
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
                  if type(watch.globPattern) == "table" and watch.globPattern.baseUri then
                    return vim.loop.fs_stat(vim.uri_to_fname(watch.globPattern.baseUri)) ~= nil
                  end
                  return true -- Keep watchers without baseUri (string patterns)
                end)
                :totable()
              
              -- If solution is already loaded, let registration through normally
              if M.solution_loaded[client_id] then
                -- Let it through, already filtered
              else
                -- Cache the entire registration (will register in bulk on solution/open)
                if not M.pending_watchers[client_id] then
                  M.pending_watchers[client_id] = {}
                end
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
        local workspace_job = M.state[client.id]
        if workspace_job and type(workspace_job) == "function" then vim.defer_fn(function()
          workspace_job(true)
          M.state[client.id] = nil
          -- Register all collected watchers in bulk after solution/project is ready
          M.register_watchers_bulk(client)
          -- Mark solution as loaded - future registrations will go through normally
          M.solution_loaded[client.id] = true
        end, 2000) end
        vim.defer_fn(function() refresh_diag(client) end, 500)
      end,
      ["workspace/_roslyn_projectNeedsRestore"] = function(_, params, ctx, _)
        local paths = params.projectFilePaths or {}
        local csproj_files = vim.tbl_filter(function(path) return path:match("%.csproj$") end, paths)

        if vim.tbl_isempty(csproj_files) then return {} end

        local restore = #csproj_files == 1 and csproj_files[1] or sln_parse.try_get_selected_solution_file()

        if restore then
          dotnet_client:initialize(function()
            dotnet_client.nuget:nuget_restore(restore, function()
              local client = vim.lsp.get_client_by_id(ctx.client_id)
              if not client then return end
              vim.defer_fn(function() refresh_diag(client) end, 500)
              --TODO: any events we can listen to?
              vim.defer_fn(function() refresh_diag(client) end, 15000)
            end)
          end)
        end

        return {}
      end,
    },
    settings = opts.config.settings,
  }

  vim.lsp.enable(constants.lsp_client_name)
end

return M
