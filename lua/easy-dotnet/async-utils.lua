local M = {}
---@alias JobCallback fun(stdout: string[], stderr: string[], exit_code: number)

--- Runs a command asynchronously using `vim.fn.jobstart`.
--- @param cmd string[] Command and its arguments.
--- @param callback JobCallback The callback function invoked with stdout, stderr, and exit code.
M.job_run_async = function(cmd, callback)
  local stdout_data = 
  {}
  local stderr_data = {}

  local function on_exit(_, exit_code) callback(stdout_data, stderr_data, exit_code) end

  local function on_stdout(_, data) stdout_data = data end

  local function on_stderr(_, data) stderr_data = data end

  vim.fn.jobstart(cmd, {
    on_stdout = on_stdout,
    on_stderr = on_stderr,
    on_exit = on_exit,
    stdout_buffered = true,
    stderr_buffered = true,
  })
end

-- await: Function to suspend a coroutine until an async function completes
-- Must be wrapped in a coroutine
--- Wraps an async function, suspending the coroutine until the job completes.
--- @param async_function fun(cmd: string[], callback: JobCallback)
--- @return fun(...: any): string[], string[], number
M.await = function(async_function)
  return function(...)
    local co = coroutine.running()
    assert(co, "await function must be called within a coroutine")

    async_function(..., function(stdout, stderr, exit_code) coroutine.resume(co, stdout, stderr, exit_code) end)

    return coroutine.yield()
  end
end

return M
