-- sys_monitor.lua
local M = {}
local _monitor_view = nil

function M.setup(opts)
  opts = opts or {}
  -- Just store a reference to the monitor module
  _monitor_view = require("easy-dotnet.netcoredbg.montior")
end

function M.route_message(method, params)
  if not _monitor_view then M.setup() end
  _monitor_view.route_message(method, params)
end

function M.get_graphs()
  if not _monitor_view then M.setup() end
  -- Return the original instances, not new ones
  local MonitorView = require("easy-dotnet.netcoredbg.montior")
  return {
    cpu = MonitorView.get_cpu_instance(),
    mem = MonitorView.get_mem_instance(),
  }
end

function M.close_all()
  if _monitor_view then _monitor_view.close_all() end
end

function M.is_open()
  if not _monitor_view then return false end
  return _monitor_view.is_open()
end

return M
