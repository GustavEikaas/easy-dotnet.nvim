local extensions = require("easy-dotnet.extensions")
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
      root_dir = function(bufnr, cb) cb("C:/Users/Gustav/repo/easy-dotnet-server-test") end,
      on_init = function(client)
        vim.notify("[easy-dotnet] LSP initialized for " .. client.name, vim.log.levels.INFO)
        local sln_path = "C:/Users/Gustav/repo/easy-dotnet-server-test/EasyDotnet.sln"

        local sln_uri = vim.uri_from_fname(sln_path)

        vim.notify("[easy-dotnet] Sending solution/open ", vim.log.levels.INFO)
        client:notify("solution/open", {
          solution = sln_uri,
        })
      end,
      on_exit = function(_, code) vim.notify("[easy-dotnet] LSP exited with code " .. code, vim.log.levels.WARN) end,
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
