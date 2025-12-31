local M = {}
---@alias easy-dotnet.Job.Callback fun(stdout: string[], stderr: string[], exit_code: number)

--- Runs a command asynchronously using `vim.fn.jobstart`.
--- @param cmd string[] Command and its arguments.
--- @param callback JobCallback The callback function invoked with stdout, stderr, and exit code.
M.job_run_async = function(cmd, callback)
  local stdout_data = {}
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

--- Await a callback-style async function inside a coroutine.
---
--- Wraps a function like `job_run_async` so you can use it in a coroutine-style flow.
---
--- Example:
--- ```lua
--- local async = require("path.to.this.module")
---
--- coroutine.wrap(function()
---   local res = async.await(async.job_run_async)({ "dotnet", "build", "project.csproj" })
---   if res.success then
---     vim.notify("Build succeeded")
---   else
---     vim.notify("Build failed: " .. table.concat(res.stderr, "\n"), vim.log.levels.ERROR)
---   end
--- end)()
--- ```
---
--- @param async_function fun(cmd: string[], callback: easy-dotnet.Job.Callback)
--- @return fun(cmd: string[]): { stdout: string[], stderr: string[], exit_code: number, success: boolean }
M.await = function(async_function)
  return function(...)
    local co = coroutine.running()
    assert(co, "await function must be called within a coroutine")

    async_function(..., function(stdout, stderr, exit_code) coroutine.resume(co, { stdout = stdout, stderr = stderr, exit_code = exit_code, success = exit_code == 0 }) end)

    return coroutine.yield()
  end
end

return M
