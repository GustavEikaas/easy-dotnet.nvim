-- sys_monitor_dap_ui.lua
local M = {}

local monitor_core = require("easy-dotnet.netcoredbg.sys_monitor")

---@class MonitorElement : dapui.Element
local MonitorElement = {}

function MonitorElement.new(graph_type)
  local self = {
    graph_type = graph_type,
    _buf = nil,
  }

  function self.render()
    -- Create buffer if it doesn't exist
    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then
      self._buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(self._buf, "bufhidden", "wipe")
      vim.api.nvim_buf_set_option(self._buf, "filetype", "monitorgraph")
    end

    local graphs = monitor_core.get_graphs()
    if not graphs or not graphs[graph_type] then return end
    local graph = graphs[graph_type]

    -- Track this buffer for updates
    graph:track_buffer(self._buf)

    -- Set highlights
    local hi_name = "GraphHi_" .. tostring(self._buf)
    vim.cmd(string.format("hi %s guifg=%s gui=bold", hi_name, graph.color))
    pcall(vim.fn.matchadd, "Comment", "[0-9.]\\+[KMGTB%s]\\+\\|│\\|─\\|┤\\|┼")

    -- Initial render (will use defaults if window not found yet, or update immediately)
    graph:render_to_buffer(self._buf)
  end

  function self.buffer()
    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then self.render() end
    return self._buf
  end

  -- These defaults are for when DAP-UI first creates the floating window
  -- Once created, our Responsive Core takes over the actual size inside.
  self.float_defaults = function() return { width = 60, height = 15, enter = false } end

  self.allow_without_session = false

  return self
end

function M.setup()
  local ok, dapui = pcall(require, "dapui")
  if not ok then
    vim.notify("nvim-dap-ui not found", vim.log.levels.WARN)
    return
  end

  dapui.register_element("netcoredbg_cpu", MonitorElement.new("cpu"))
  dapui.register_element("netcoredbg_mem", MonitorElement.new("mem"))

  vim.notify("Registered netcoredbg monitor elements.", vim.log.levels.INFO)
end

return M
