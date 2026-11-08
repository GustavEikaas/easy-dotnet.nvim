local nio = require("nio")
local events = require("easy-dotnet.neotest.events")

local M = {}

local TERMINAL_TYPES = {
  Passed = true,
  Failed = true,
  Faulted = true,
  Skipped = true,
  Inconclusive = true,
  Cancelled = true,
  BuildFailed = true,
}

---@class easy-dotnet.neotest.RunContext
---@field leaf_ids table<string, boolean>
---@field completion nio.control.Future
---@field result_chan nio.control.Queue

---@param leaf_ids string[] All leaf position IDs (type == "test") in the subtree
---@return easy-dotnet.neotest.RunContext
function M.begin_run(leaf_ids)
  local leaf_set = {}
  for _, id in ipairs(leaf_ids) do
    leaf_set[id] = true
  end

  ---@class easy-dotnet.neotest.RunContext
  local ctx = {
    leaf_ids = leaf_set,
    completion = nio.control.future(),
    result_chan = nio.control.queue(),
    _stdout = {},
  }

  local unsubscribe_status = events.subscribe("updateStatus", function(id, status) ctx:on_update(id, status) end)
  -- A force-kill may leave the run request unanswered; the Killed broadcast is the last word.
  local unsubscribe_runner = events.subscribe("runnerStatus", function(status)
    if status.overallStatus == "Killed" then ctx:fail("Test run was killed") end
  end)
  local function unsubscribe()
    unsubscribe_status()
    unsubscribe_runner()
  end

  function ctx:on_update(id, status)
    local status_type = status and status.type or ""
    if not TERMINAL_TYPES[status_type] then return end

    if self.leaf_ids[id] then self.result_chan.put_nowait(vim.json.encode({ id = id, status = status }) .. "\n") end

    -- Other projects in the same run keep going; the run ends with the server response.
    if status_type == "BuildFailed" then
      table.insert(self._stdout, "Build has failed")
      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      client.testrunner:get_build_errors(id)
    end
  end

  --- Ends the run once the server has answered the run/debug request.
  --- Deferred one tick: status notifications sent before the response are emitted from
  --- a nested vim.schedule, so this lets them reach the output stream first.
  ---@param code integer
  function ctx:finish(code)
    vim.schedule(function()
      if self.completion.is_set() then return end
      unsubscribe()
      self.result_chan.put_nowait(nil)
      self.completion.set(code)
    end)
  end

  ---@param message string
  function ctx:fail(message)
    table.insert(self._stdout, message)
    self:finish(1)
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

  return ctx
end

return M
