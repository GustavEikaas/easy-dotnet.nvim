local M = {}

function M.start()
  local rpc = require("easy-dotnet.rpc.rpc").global_rpc_client

  rpc:initialize(function()
    local roslyn_pipe = [[\\.\pipe\EasyDotnet_ClientPipe]]

    vim.lsp.config.easy_dotnet = {
      name = "easy_dotnet",
      filetypes = { "cs" },
      cmd = vim.lsp.rpc.connect(roslyn_pipe),
      root_dir = function(bufnr, cb) cb("C:/Users/gusta/repo/easy-dotnet-server-test") end,
      on_init = function(client) vim.notify("[easy-dotnet] LSP initialized for " .. client.name, vim.log.levels.INFO) end,
      on_exit = function(_, code) vim.notify("[easy-dotnet] LSP exited with code " .. code, vim.log.levels.WARN) end,
    }

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "cs",
      callback = function()
        local client_name = "easy_dotnet"
        local buf = vim.api.nvim_get_current_buf()

        local existing = vim.tbl_filter(function(c) return c.name == client_name end, vim.lsp.get_clients())
        if #existing > 0 then
          for _, c in ipairs(existing) do
            if not vim.tbl_contains(c.attached_buffers, buf) then c.attach_buffers(buf) end
          end
          return
        end

        vim.lsp.start(vim.lsp.config.easy_dotnet)
      end,
    })
  end)
end

return M
