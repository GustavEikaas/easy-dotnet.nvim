local M = {}

--- Benchmarks a function by measuring its execution time and logging the result.
---
--- @param name string: A label used to identify the function being benchmarked in logs.
--- @param fn fun(...) The function to benchmark.
--- @param ... any: Arguments to pass to the function.
--- @return any: Returns whatever the input function returns.
function M.benchmark(name, fn, ...)
  ---@diagnostic disable-next-line: undefined-field
  local start_time = vim.loop.hrtime()
  local results = fn(...)
  ---@diagnostic disable-next-line: undefined-field
  local end_time = vim.loop.hrtime()
  local elapsed_ms = (end_time - start_time) / 1e6

  print(string.format("[benchmark] %s took %.2f ms", name, elapsed_ms))
  return results
end

return M
