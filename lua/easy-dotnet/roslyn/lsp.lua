local root_finder = require("easy-dotnet.roslyn.root_finder")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local options = require("easy-dotnet.options")
local logger = require("easy-dotnet.logger")

local M = {}

---@type vim.lsp.ClientConfig
local base_config = {
  name = constants.lsp_client_name,
  filetypes = { "cs" },
  cmd = { "dotnet", "easydotnet", "roslyn", "start" },
  capabilities = vim.lsp.protocol.make_client_capabilities(),
  on_init = function(client)
    local buf = vim.api.nvim_get_current_buf()
    local fname = vim.api.nvim_buf_get_name(buf)
    if not fname or #fname == 0 then return end
    local uri = vim.uri_from_fname(fname)
    if fname:match("%.slnx?$") then
      client:notify("solution/open", { solution = uri })
    elseif fname:match("%.csproj$") then
      client:notify("project/open", { projects = { uri } })
    end
  end,
  handlers = {
    ["workspace/projectInitializationComplete"] = function(_, _, ctx)
      local client = vim.lsp.get_client_by_id(ctx.client_id)
      if not client then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      client:notify("textDocument/didChange", {
        textDocument = { uri = vim.uri_from_bufnr(bufnr), version = 0 },
        contentChanges = {},
      })
    end,
  },
}

local function find_root(bufnr, callback)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  if not buf_path or buf_path == "" then return end

  local project = root_finder.find_csproj_from_file(buf_path)
  if not project then return callback(vim.fs.dirname(buf_path), buf_path) end

  local sln = root_finder.find_solutions_from_file(project)
  if vim.tbl_isempty(sln) then return callback(vim.fs.dirname(project), project) end

  local sln_default = sln_parse.try_get_selected_solution_file()
  if sln_default then
    for _, s in ipairs(sln) do
      if vim.fs.basename(s) == vim.fs.basename(sln_default) then return callback(vim.fs.dirname(s), s) end
    end
  end

  require("easy-dotnet.picker").picker(
    nil,
    vim.tbl_map(function(v) return { display = v } end, sln),
    function(choice) callback(vim.fs.dirname(choice.display), choice.display) end,
    "Pick solution file to start Roslyn from",
    true,
    true
  )
end

function M.enable()
  if vim.fn.has("nvim-0.11") == 0 then
    logger.warn("easy-dotnet LSP requires Neovim 0.11+")
    return
  end

  vim.api.nvim_create_autocmd("FileType", {
    pattern = "cs",
    callback = function(args)
      local bufnr = args.buf
      local path = vim.api.nvim_buf_get_name(bufnr)
      if not path or path == "" or vim.fn.filereadable(path) == 0 then return end

      find_root(bufnr, function(root)
        local user_lsp_config = options.get_option("lsp").config or {}
        local config = vim.tbl_deep_extend("force", base_config, user_lsp_config, {
          root_dir = root,
        })

        vim.lsp.start(config)
      end)
    end,
  })
end

vim.lsp.enable(constants.lsp_client_name)

return M
