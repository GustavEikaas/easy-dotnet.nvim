local nio = require("nio")
local events = require("easy-dotnet.neotest.events")

local M = {}

local TERMINAL_TYPES = {
  Passed = true,
  Failed = true,
  Faulted = true,
  Skipped = true,
  Cancelled = true,
  BuildFailed = true,
}

---@class easy-dotnet.neotest.RunContext
---@field root_node_id string
---@field leaf_ids table<string, boolean>
---@field completion nio.control.Future
---@field result_chan nio.control.Queue
---@field done boolean

---@type easy-dotnet.neotest.RunContext|nil
local current = nil

events.subscribe("updateStatus", function(id, status)
  if not current then return end
  current:on_update(id, status)
end)

---@param root_id string  The node ID that was passed to testrunner/run
---@param leaf_ids string[] All leaf position IDs (type == "test") in the subtree
---@return easy-dotnet.neotest.RunContext
function M.begin_run(root_id, leaf_ids)
  local leaf_set = {}
  for _, id in ipairs(leaf_ids) do
    leaf_set[id] = true
  end

  ---@type easy-dotnet.neotest.RunContext
  local ctx = {
    root_node_id = root_id,
    leaf_ids = leaf_set,
    completion = nio.control.future(),
    result_chan = nio.control.queue(),
    done = false,
    _stdout = {},
  }

  function ctx:on_update(id, status)
    local status_type = status and status.type or ""
    if not TERMINAL_TYPES[status_type] then return end

    if self.leaf_ids[id] then self.result_chan.put_nowait(vim.json.encode({ id = id, status = status }) .. "\n") end

    if id == self.root_node_id then
      self.done = true
      self.result_chan.put_nowait(nil)
      self.completion.set(0)
      current = nil
    end
  end

  function ctx:flush_stdout_to_tempfile()
    local path = vim.fn.tempname()
    local f = io.open(path, "w")
    if f then
      f:write(table.concat(self._stdout, "\n"))
      f:close()
    end
    return path
  end

  current = ctx
  return ctx
end

return M
