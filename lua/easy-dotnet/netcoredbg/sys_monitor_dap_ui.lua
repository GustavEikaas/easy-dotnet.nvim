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
    end

    local graphs = monitor_core.get_graphs()
    if not graphs then return end

    local graph = graphs[graph_type]
    if not graph then return end

    local hi_name = "GraphHi_" .. tostring(self._buf)
    vim.cmd(string.format("hi %s guifg=%s gui=bold", hi_name, graph.color))

    vim.fn.matchadd("Comment", "[0-9.]\\+[KMGTB%s]\\+\\|│\\|─\\|┤\\|┼")

    graph:render_to_buffer(self._buf)
  end

  function self.buffer()
    if not self._buf or not vim.api.nvim_buf_is_valid(self._buf) then self.render() end
    return self._buf
  end

  self.float_defaults = function()
    local graphs = monitor_core.get_graphs()
    if not graphs then return { width = 75, height = 17, enter = false } end

    local graph = graphs[graph_type]
    if not graph then return { width = 75, height = 17, enter = false } end

    local AXIS_COL_WIDTH = 12
    local width = graph.width + AXIS_COL_WIDTH + 1
    local height = graph.height + 3

    return {
      width = width,
      height = height,
      enter = false,
    }
  end

  self.allow_without_session = false

  return self
end

function M.setup(opts)
  opts = opts or {}
  monitor_core.setup(opts)

  local ok, dapui = pcall(require, "dapui")
  if not ok then
    vim.notify("nvim-dap-ui not found", vim.log.levels.WARN)
    return
  end

  dapui.register_element("netcoredbg_cpu", MonitorElement.new("cpu"))
  dapui.register_element("netcoredbg_mem", MonitorElement.new("mem"))

  vim.notify("Registered netcoredbg monitor elements. Add to dapui layouts config.", vim.log.levels.INFO)
end

return M
