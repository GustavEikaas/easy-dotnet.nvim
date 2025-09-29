local extensions = require("easy-dotnet.extensions")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local M = {
  max_clients = 5,
}

---@class EasyDotnetClientStateEntry
---@field selected_file_for_init string|nil

---@type table<number, EasyDotnetClientStateEntry>
M.client_state = {}

local selected_file_for_init
---@type vim.lsp.Config
M.lsp_config = {
  name = "easy_dotnet",
  filetypes = { "cs" },
  capabilities = {
    textDocument = {
      diagnostic = {
        dynamicRegistration = true,
      },
    },
  },
  on_init = function(client)
    M.client_state[client.id] = {
      selected_file_for_init = selected_file_for_init,
    }
    if selected_file_for_init then
      local uri = vim.uri_from_fname(selected_file_for_init)
      if selected_file_for_init:match("%.slnx?$") then
        client:notify("solution/open", { solution = uri })
      elseif selected_file_for_init:match("%.csproj$") then
        client:notify("project/open", { projects = { uri } })
      end
    end
  end,
  on_exit = function(_, _, client_id)
    vim.notify("[easy-dotnet] LSP exited", vim.log.levels.WARN)
    M.client_state[client_id] = nil
  end,
  commands = {
    ["roslyn.client.fixAllCodeAction"] = function(data, ctx) vim.print("fixAllCodeAction", "data", data, "ctx", ctx) end,
    ["roslyn.client.nestedCodeAction"] = function(data, ctx) vim.print("nestedCodeAction", "data", data, "ctx", ctx) end,
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
        vim.notify("Roslyn ready")
      end, 500)
    end,
    ["workspace/_roslyn_projectNeedsRestore"] = function(_, params, ctx)
      local paths = params.projectFilePaths or {}
      local csproj_files = vim.tbl_filter(function(path) return path:match("%.csproj$") end, paths)

      if vim.tbl_isempty(csproj_files) then return {} end

      dotnet_client:initialize(function()
        local selected_file = M.client_state[ctx.client_id] and M.client_state[ctx.client_id].selected_file_for_init

        if selected_file then
          if selected_file:match("%.slnx?$") then
            dotnet_client.nuget:nuget_restore(selected_file, function() end)
          elseif selected_file:match("%.csproj$") then
            dotnet_client.nuget:nuget_restore(selected_file, function() end)
          end
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
  local function start_easy_dotnet_lsp(bufnr)
    M.find_project_or_solution(bufnr, function(root, selected_file)
      selected_file_for_init = selected_file

      local existing_clients = vim.lsp.get_clients({ name = "easy_dotnet" })

      for _, client in ipairs(existing_clients) do
        if client.config.root_dir == root then
          vim.lsp.buf_attach_client(bufnr, client.id)
          return
        end
      end

      if #existing_clients >= M.max_clients then
        vim.notify(string.format("[easy-dotnet] Cannot start new client: already %d running", M.max_clients), vim.log.levels.WARN)
        return
      end

      dotnet_client:initialize(function()
        dotnet_client.lsp:lsp_start(function(res)
          local pipe_path = get_correct_pipe_path(res.pipe)

          local lsp_opts = vim.tbl_extend("keep", {
            cmd = function(dispatchers) return vim.lsp.rpc.connect(pipe_path)(dispatchers) end,
            root_dir = root,
          }, M.lsp_config)

          vim.lsp.start(lsp_opts, { bufnr = bufnr })
        end)
      end)
    end)
  end
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "cs",
    callback = function(args)
      vim.schedule(function() start_easy_dotnet_lsp(args.buf) end)
    end,
  })
end

return M
