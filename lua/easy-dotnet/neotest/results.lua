local nio = require("nio")

local OUTCOME_MAP = {
  passed = "passed",
  failed = "failed",
  faulted = "failed",
  skipped = "skipped",
  cancelled = "skipped",
  buildfailed = "failed",
}

---@param detail easy-dotnet.TestRunner.NeotestBatchResult
---@return neotest.Result
local function to_neotest_result(detail)
  local errors = nil
  if detail.errorMessage and #detail.errorMessage > 0 then
    errors = {
      {
        message = table.concat(detail.errorMessage, "\n"),
        line = detail.failingFrame and detail.failingFrame.line or nil,
      },
    }
  end

  local output_path = vim.fn.tempname()
  local f = io.open(output_path, "w")
  if f then
    if detail.stdout and #detail.stdout > 0 then f:write(table.concat(detail.stdout, "\n")) end
    if errors then f:write("\n" .. (errors[1].message or "")) end
    f:close()
  end

  return {
    status = OUTCOME_MAP[detail.outcome or ""] or "failed",
    short = detail.errorMessage and detail.errorMessage[1] or nil,
    errors = errors,
    output = output_path,
  }
end

---@param spec neotest.RunSpec
---@param _strategy_result neotest.StrategyResult
---@param _tree neotest.Tree
---@return table<string, neotest.Result>
return function(spec, _strategy_result, _tree)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local ids = spec.context and spec.context.result_ids
  if not ids or #ids == 0 then return {} end

  local batch = nil
  local done = nio.control.future()

  client.testrunner:neotest_batch_results(ids, function(res)
    batch = res
    done.set()
  end)
  done.wait()

  if not batch then return {} end

  local out = {}
  for id, detail in pairs(batch) do
    out[id] = to_neotest_result(detail)
  end
  return out
end
