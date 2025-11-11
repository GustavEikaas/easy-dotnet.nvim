local constants = require("easy-dotnet.constants")
local root_finder = require("easy-dotnet.roslyn.root_finder")
local sln_parse = require("easy-dotnet.parsers.sln-parse")

-- options.
--     lsp = {
--       enabled = true,
--       analyzer_assemblies = {},
--       roslynator_enabled = true,
--       config = {},
--     },
-- [Description("Enable Roslynator analyzers (optional).")]
-- [CommandOption("--roslynator")]
-- public bool UseRoslynator { get; init; }
--
-- [Description("Additional analyzer assemblies to load.")]
-- [CommandOption("--analyzer <PATH>")]
-- public string[] AnalyzerAssemblies { get; init; } = [];

local function find_project_or_solution(bufnr, cb)
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

---@type vim.lsp.Config
return {
  name = constants.lsp_client_name,
  filetypes = { "cs" },
  cmd = { "dotnet", "easydotnet", "roslyn", "start" },
  capabilities = {
    textDocument = {
      -- HACK: Doesn't show any diagnostics if we do not set this to true
      diagnostic = {
        dynamicRegistration = true,
      },
    },
  },
  root_dir = function(bufnr, on_dir) find_project_or_solution(bufnr, on_dir) end,
  on_init = function(client) vim.print("roslyn starting...") end,
  on_exit = function(code, _, client_id)
    --TODO: exit code
    vim.schedule(function() vim.notify("[easy-dotnet] Roslyn stopped", vim.log.levels.WARN) end)
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
      end, 500)
    end,
    ["workspace/_roslyn_projectNeedsRestore"] = function(_, params, ctx)
      local paths = params.projectFilePaths or {}
      local csproj_files = vim.tbl_filter(function(path) return path:match("%.csproj$") end, paths)

      if vim.tbl_isempty(csproj_files) then return {} end

      --TODO: restore
      vim.print(csproj_files)

      -- dotnet_client:initialize(function()
      --   if selected_file then
      --     dotnet_client.nuget:nuget_restore(selected_file, function() end)
      --     return
      --   end
      -- end)

      return {}
    end,
  },
}
