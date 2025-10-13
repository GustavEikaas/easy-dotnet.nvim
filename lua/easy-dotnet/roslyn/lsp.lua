local extensions = require("easy-dotnet.extensions")
local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local options = require("easy-dotnet.options")

local M = {
  max_clients = 5,
}

local function get_running_lsp_clients()
  return vim.iter(vim.lsp.get_clients({ name = constants.lsp_client_name })):filter(function(client) return not client:is_stopped() end):totable()
end

---@class EasyDotnetClientStateEntry
---@field selected_file_for_init string|nil

---@type table<number, EasyDotnetClientStateEntry>
M.client_state = {}

local roslyn_starting
local selected_file_for_init
---@type vim.lsp.Config
M.lsp_config = {
  name = constants.lsp_client_name,
  filetypes = { "cs" },
  capabilities = {
    textDocument = {
      diagnostic = {
        dynamicRegistration = true,
      },
    },
  },
  on_init = function(client)
    roslyn_starting = job.register_job({ name = "Roslyn starting", on_error_text = "Roslyn failed to start", on_success_text = "Roslyn started" })
    M.client_state[client.id] = {
      selected_file_for_init = selected_file_for_init,
    }
    if selected_file_for_init then
      local uri = vim.uri_from_fname(selected_file_for_init)
      if selected_file_for_init:match("%.slnx?$") then
        client:notify("solution/open", { solution = uri })
      elseif selected_file_for_init:match("%.csproj$") then
        client:notify("project/open", { projects = { uri } })
      else
        roslyn_starting(true)
      end
    end
  end,
  on_exit = function(_, _, client_id)
    vim.schedule(function() vim.notify("[easy-dotnet] Roslyn stopped", vim.log.levels.WARN) end)
    M.client_state[client_id] = nil
  end,
  commands = {
    ["roslyn.client.fixAllCodeAction"] = require("easy-dotnet.roslyn.lsp.fix_all_code_action"),
    ["roslyn.client.nestedCodeAction"] = require("easy-dotnet.roslyn.lsp.nested_code_action"),
  },
  handlers = {
    ["workspace/projectInitializationComplete"] = function(_, _, ctx, _)
      vim.defer_fn(function()
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
        if roslyn_starting then
          roslyn_starting(true)
          roslyn_starting = nil
        end
      end, 500)
    end,
    ["workspace/_roslyn_projectNeedsRestore"] = function(_, params, ctx)
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

function M.find_project_or_solution(bufnr, cb)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local project = root_finder.find_csproj_from_file(buf_path)
  local selected_file

  if not project then
    selected_file = buf_path
    cb(vim.fs.dirname(selected_file), selected_file)
    return
  end

  local sln = root_finder.find_solutions_from_file(project)

  if vim.tbl_isempty(sln) then
    selected_file = project
    cb(vim.fs.dirname(selected_file), selected_file)
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
    selected_file = selected_sln
    cb(vim.fs.dirname(selected_file), selected_file)
    return
  end

  require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(value) return { display = value } end, sln), function(r)
    selected_file = r.display
    cb(vim.fs.dirname(selected_file), selected_file)
  end, "Pick solution file to start Roslyn from", true, true)
end

local function get_correct_pipe_path(roslyn_pipe)
  if extensions.isWindows() then
    return [[\\.\pipe\]] .. roslyn_pipe
  elseif extensions.isDarwin() then
    return os.getenv("TMPDIR") .. "CoreFxPipe_" .. roslyn_pipe
  else
    return "/tmp/CoreFxPipe_" .. roslyn_pipe
  end
end

function M.enable()
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires neovim 0.11 or higher ")
    return
  end

  local function start_easy_dotnet_lsp(bufnr)
    M.find_project_or_solution(bufnr, function(root, selected_file)
      selected_file_for_init = selected_file

      local existing_clients = get_running_lsp_clients()

      for _, client in ipairs(existing_clients) do
        if client.config.root_dir == root or root:match("/MetadataAsSource/") then
          vim.lsp.buf_attach_client(bufnr, client.id)
          return
        end
      end

      if #existing_clients >= M.max_clients then
        vim.notify(string.format("[easy-dotnet] Cannot start new client: already %d running", M.max_clients), vim.log.levels.WARN)
        return
      end

      dotnet_client:initialize(function()
        if not dotnet_client.has_lsp then
          vim.defer_fn(function() logger.warn("Roslyn LSP unable to start, server outdated. :Dotnet _server update") end, 500)
          return
        end
        dotnet_client.lsp:lsp_start(function(res)
          local pipe_path = get_correct_pipe_path(res.pipe)

          local user_lsp_config = options.get_option("lsp").config or {}

          local lsp_opts = vim.tbl_deep_extend("force", M.lsp_config, user_lsp_config, {
            cmd = function(dispatchers) return vim.lsp.rpc.connect(pipe_path)(dispatchers) end,
            root_dir = root,
          })

          vim.lsp.start(lsp_opts, { bufnr = bufnr })
        end)
      end)
    end)
  end
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "cs",
    callback = function(args)
      local path = vim.api.nvim_buf_get_name(args.buf)
      if not path or #path == 0 then return end
      if vim.fn.filereadable(path) == 0 then return end
      start_easy_dotnet_lsp(args.buf)
    end,
  })
end

return M
