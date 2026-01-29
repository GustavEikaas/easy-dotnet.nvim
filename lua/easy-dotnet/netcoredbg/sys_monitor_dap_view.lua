local M = {}

local monitor_core = require("easy-dotnet.netcoredbg.monitor_core")

---@class NetcoredbgMonitorSection
local function create_monitor_section(graph_type, title)
  return {
    title = title,
    buffer = function()
      local graphs = monitor_core.get_graphs()
      local graph = graphs[graph_type]

      if graph.buf == -1 or not vim.api.nvim_buf_is_valid(graph.buf) then
        graph.buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_option(graph.buf, "bufhidden", "wipe")
        vim.api.nvim_buf_set_option(graph.buf, "filetype", "monitorgraph")

        local hi_name = "GraphHi_" .. tostring(graph.buf)
        vim.cmd(string.format("hi %s guifg=%s gui=bold", hi_name, graph.color))

        graph:render_to_buffer(graph.buf)
      end

      return graph.buf
    end,
  }
end

function M.setup(opts)
  opts = opts or {}
  monitor_core.setup(opts)

  local ok, dapview = pcall(require, "nvim-dap-view")
  if not ok then
    vim.notify("nvim-dap-view not found", vim.log.levels.WARN)
    return
  end

  dapview.register_section("netcoredbg_cpu", create_monitor_section("cpu", "CPU Monitor"))
  dapview.register_section("netcoredbg_mem", create_monitor_section("mem", "Memory Monitor"))

  vim.notify("Registered netcoredbg monitor sections for dap-view", vim.log.levels.INFO)
end

return M
