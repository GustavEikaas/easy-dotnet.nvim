local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")

local M = {}

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

function M.enable()
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end

  ---@type vim.lsp.Config
  vim.lsp.config[constants.lsp_client_name] = {
    cmd = { "dotnet", "easydotnet", "roslyn", "start", "--roslynator" },
    filetypes = { "cs" },
    root_dir = M.find_project_or_solution,
    capabilities = {
      textDocument = {
        diagnostic = {
          dynamicRegistration = true,
        },
      },
    },
    on_init = function(client)
      local file, type = M.find_sln_or_csproj(client.root_dir)
      if not file then return end

      local uri = vim.uri_from_fname(file)
      if type == "sln" then
        client:notify("solution/open", { solution = uri })
      elseif type == "csproj" then
        client:notify("project/open", { projects = { uri } })
      else
      end
    end,
    on_exit = function(code, signal, client_id)
      vim.schedule(function()
        vim.print(code)
        vim.print(signal)
        vim.print(client_id)
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

        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end

        local params = {
          textDocument = {
            uri = vim.uri_from_bufnr(bufnr),
            version = vim.lsp.util.buf_versions[bufnr] or 0,
          },
          contentChanges = {},
        }

        client:notify("textDocument/didChange", params)
        vim.print("Workspace ready")
      end,
      ["workspace/_roslyn_projectNeedsRestore"] = function(_, params, ctx, _)
        local paths = params.projectFilePaths or {}
        local csproj_files = vim.tbl_filter(function(path) return path:match("%.csproj$") end, paths)

        if vim.tbl_isempty(csproj_files) then return {} end

        dotnet_client:initialize(function()
          local selected_file = M.client_state[ctx.client_id] and M.client_state[ctx.client_id].selected_file_for_init

          if selected_file then
            dotnet_client.nuget:nuget_restore(selected_file, function() end)
            return
          end
        end)

        return {}
      end,
    },
  }

  vim.lsp.enable(constants.lsp_client_name)
end

return M
