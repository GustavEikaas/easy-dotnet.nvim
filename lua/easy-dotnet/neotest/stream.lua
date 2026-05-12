local nio = require("nio")

local TERMINAL_STATUSES = {
  Passed = "passed",
  Failed = "failed",
  Faulted = "failed",
  Skipped = "skipped",
  Cancelled = "skipped",
  BuildFailed = "failed",
}

---@param output_iter fun(): string[] Async line iterator from lib.files.split_lines
---@return fun(): table<string, neotest.Result>|nil Async iterator of partial results
return function(output_iter)
  local q = nio.control.queue()

  nio.run(function()
    for lines in output_iter do
      for _, line in ipairs(lines) do
        local ok, update = pcall(vim.json.decode, line)
        if ok and update and update.id and update.status then
          local nstatus = TERMINAL_STATUSES[update.status.type or ""] or "failed"
          q.put({ [update.id] = { status = nstatus } })
        end
      end
    end
    q.put(nil)
  end)

  return q.get
end
