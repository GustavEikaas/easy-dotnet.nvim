local M = {}

--- Requests the generated SQL for the EF Core query at the given position and
--- shows it in a centered float. Shared by `:Dotnet ef sql` and the
--- "View generated SQL" code action.
---@param file_path string
---@param line integer 0-based line
---@param character integer 0-based character
function M.show(file_path, line, character)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  client:initialize(function()
    client.roslyn:ef_generated_sql(file_path, line, character, function(res)
      for _, warning in ipairs(res.warnings or {}) do
        vim.notify(warning, vim.log.levels.WARN)
      end
      if not res.success then
        vim.notify(res.errorMessage or "Failed to generate SQL", vim.log.levels.WARN)
        return
      end
      local Window = require("easy-dotnet.test-runner.window")
      Window.new_float():pos_center():write_buf(vim.split(res.sql, "\n")):buf_set_filetype("sql"):create()
    end)
  end)
end

return M
