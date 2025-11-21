local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")

local M = {
  state = {},
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

  require("easy-dotnet.picker").picker(
    nil,
    vim.tbl_map(function(value) return { display = value } end, sln),
    function(r) cb(vim.fs.dirname(r.display)) end,
    "Pick solution file to start Roslyn from",
    true,
    true
  )
end

function M.find_sln_or_csproj(dir)
  local sln = vim.fs.find(function(name) return name:match("%.slnx?$") end, { path = dir, upward = false, limit = 1 })
  if sln[1] then return sln[1], "sln" end

  local csproj = vim.fs.find(function(name) return name:match("%.csproj$") end, { path = dir, upward = false, limit = 1 })
  if csproj[1] then return csproj[1], "csproj" end

  return nil
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

---@param opts LspOpts
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

  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_client_name] = {
    cmd = cmd,
    filetypes = { "cs" },
    root_dir = M.find_project_or_solution,
    capabilities = {
      textDocument = {
        diagnostic = {
          dynamicRegistration = true,
        },
      },
      workspace = {
        didChangeWatchedFiles = {
          dynamicRegistration = true,
        },
      },
    },
    on_init = function(client)
      local file, type = M.find_sln_or_csproj(client.root_dir)
      if not file then return end

      local uri = vim.uri_from_fname(file)
      if type == "sln" then
        M.state[client.id] = job.register_job({ name = "Opening solution", on_error_text = "Failed to open solution", on_success_text = "Workspace ready", timeout = 15000 })
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
      vim.schedule(function()
        if code ~= 0 and code ~= 143 then
          vim.notify("[easy-dotnet] Roslyn crashed", vim.log.levels.ERROR)
          return
        end
        vim.notify("[easy-dotnet] Roslyn stopped", vim.log.levels.INFO)
      end)
    end,
    commands = {
      ["roslyn.client.fixAllCodeAction"] = require("easy-dotnet.roslyn.lsp.fix_all_code_action"),
      ["roslyn.client.nestedCodeAction"] = require("easy-dotnet.roslyn.lsp.nested_code_action"),
    },
    handlers = {
      ["workspace/projectInitializationComplete"] = function(_, _, ctx, _)
        local client = vim.lsp.get_client_by_id(ctx.client_id)
        if not client then return end
        local workspace_job = M.state[client.id]
        if workspace_job and type(workspace_job) == "function" then vim.defer_fn(function()
          workspace_job(true)
          M.state[client.id] = nil
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
