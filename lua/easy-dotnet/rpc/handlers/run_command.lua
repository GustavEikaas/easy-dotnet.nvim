---@class easy-dotnet.Job.TrackedJob
---@field jobId string
---@field command easy-dotnet.Server.RunCommand

---@class easy-dotnet.Server.RunCommand
---@field executable string The executable to run (e.g., "dotnet")
---@field arguments string[] List of command-line arguments
---@field workingDirectory string Working directory for the command
---@field environmentVariables table<string, string> Environment variables to set

---@param params easy-dotnet.Job.TrackedJob
return function(params, response, throw, validate)
  vim.print("command recieved")
  local job_id_ok, job_id_err = validate({ jobId = "string" }, params)
  if not job_id_ok then
    throw({ code = -32602, message = job_id_err })
    return
  end

  local command = params.command
  if not command then
    throw({ code = -32602, message = "Missing nested 'command' object" })
    return
  end

  local cmd = vim.list_extend({ command.executable }, command.arguments or {})

  local job_id = vim.fn.jobstart(cmd, {
    cwd = command.workingDirectory,
    env = command.environmentVariables,
    term = true,
    on_exit = function(_, exit_code, _)
      local client = require("easy-dotnet.rpc.rpc").global_rpc_client
      if client._initialized then client._client.notify("processExited", { jobId = params.jobId, exitCode = exit_code }) end
    end,
  })

  if job_id <= 0 then
    throw({ code = -32000, message = "Failed to start terminal job" })
    return
  end

  local pid_ok, pid = pcall(vim.fn.jobpid, job_id)

  response({ processId = pid_ok and pid or -1 })
end
