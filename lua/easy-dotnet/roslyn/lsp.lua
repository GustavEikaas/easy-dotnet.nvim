local extensions = require("easy-dotnet.extensions")
local dotnet_client = require("easy-dotnet.rpc.rpc").global_rpc_client
local logger = require("easy-dotnet.logger")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local csproj_parse = require("easy-dotnet.parsers.csproj-parse")
local M = {}

function M.start()
  local rpc = require("easy-dotnet.rpc.rpc").global_rpc_client

  rpc:initialize(function()
    local roslyn_pipe = require("easy-dotnet.rpc.dotnet-client").roslyn_pipe
    if not roslyn_pipe then error("No roslyn pipe") end

    local full_pipe_path
    if extensions.isWindows() then
      full_pipe_path = [[\\.\pipe\]] .. roslyn_pipe
    elseif extensions.isDarwin() then
      full_pipe_path = os.getenv("TMPDIR") .. "CoreFxPipe_" .. roslyn_pipe
    else
      full_pipe_path = "/tmp/CoreFxPipe_" .. roslyn_pipe
    end

    vim.lsp.config.easy_dotnet = {
      name = "easy_dotnet",
      filetypes = { "cs" },
      cmd = vim.lsp.rpc.connect(full_pipe_path),
      capabilities = {
        textDocument = {
          diagnostic = {
            dynamicRegistration = true,
          },
        },
      },
      root_dir = function(bufnr, cb)
        local sln = sln_parse.try_get_selected_solution_file()

        if sln then
          local full_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), sln))
          cb(vim.fs.dirname(full_path))
          return
        end

        local proj = csproj_parse.find_csproj_file()
        if proj then
          cb(vim.fs.dirname(proj))
          return
        end
        logger.warn("Failed to find solution file and or project file")
        local buf_path = vim.api.nvim_buf_get_name(bufnr)
        cb(vim.fs.dirname(buf_path))
      end,
      on_init = function(client)
        vim.notify("Roslyn loading", vim.log.levels.INFO)

        local sln = sln_parse.try_get_selected_solution_file()
        if sln then
          local full_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), sln))
          local sln_uri = vim.uri_from_fname(full_path)
          -- vim.notify("[easy-dotnet] Sending solution/open " .. full_path, vim.log.levels.INFO)
          client:notify("solution/open", {
            solution = sln_uri,
          })
          return
        end

        local proj = csproj_parse.find_csproj_file()
        if proj then
          -- vim.notify("[easy-dotnet] Sending project/open " .. proj, vim.log.levels.INFO)
          client:notify("project/open", {
            projects = { vim.uri_from_fname(proj) },
          })
          return
        end
        vim.notify("[easy-dotnet] No solution or project found to open", vim.log.levels.WARN)
      end,
      on_exit = function() vim.notify("[easy-dotnet] LSP exited", vim.log.levels.WARN) end,
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
            vim.print("Roslyn ready")
          end, 500)
        end,
        ["workspace/_roslyn_projectNeedsRestore"] = function(_, params)
          local paths = params.projectFilePaths or {}
          local csproj_files = vim.tbl_filter(function(path) return path:match("%.csproj$") end, paths)

          if vim.tbl_isempty(csproj_files) then return {} end

          dotnet_client:initialize(function()
            local sln = sln_parse.try_get_selected_solution_file()
            if sln and #csproj_files > 1 then
              local full_path = vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), sln))
              dotnet_client.nuget:nuget_restore(full_path, function() end)
              return
            end

            local proj = csproj_files[1]
            dotnet_client.nuget:nuget_restore(proj, function() end)
          end)

          return {}
        end,
      },
    }

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "cs",
      callback = function()
        local client_name = "easy_dotnet"
        local buf = vim.api.nvim_get_current_buf()

        local existing = vim.lsp.get_clients({ name = client_name })
        if #existing > 0 then
          for _, client in ipairs(existing) do
            if not vim.lsp.buf_is_attached(buf, client.id) then vim.lsp.buf_attach_client(buf, client.id) end
          end
          return
        end

        vim.lsp.start(vim.lsp.config.easy_dotnet)
      end,
    })
  end)
end

return M
