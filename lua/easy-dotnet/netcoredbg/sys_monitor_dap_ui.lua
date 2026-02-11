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
    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then
      self._buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_option(self._buf, "bufhidden", "wipe")
      vim.api.nvim_buf_set_option(self._buf, "filetype", "monitorgraph")
      vim.api.nvim_buf_call(self._buf, function() vim.cmd([[syntax match Comment "[0-9.]\+[KMGTB%s]\+\|│\|─\|┤\|┼"]]) end)
    end

    local graphs = monitor_core.get_graphs()
    if not graphs or not graphs[graph_type] then return end
    local graph = graphs[graph_type]

    graph:track_buffer(self._buf)

    local hi_name = "GraphHi_" .. tostring(self._buf)
    vim.cmd(string.format("hi %s guifg=%s gui=bold", hi_name, graph.color))

    graph:render_to_buffer(self._buf)
  end

  function self.buffer()
    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then self.render() end
    return self._buf
  end

  self.float_defaults = function() return { width = 60, height = 15, enter = false } end

  self.allow_without_session = false

  return self
end

function M.setup()
  local ok, dapui = pcall(require, "dapui")
  if not ok then return end

  dapui.register_element("easy-dotnet_cpu", MonitorElement.new("cpu"))
  dapui.register_element("easy-dotnet_mem", MonitorElement.new("mem"))
end

return M
