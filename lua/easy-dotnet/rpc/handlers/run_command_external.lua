local function get_state() return require("easy-dotnet.terminal").state end

---Merges provided env vars with the system environment into the KEY=VALUE
---string list format required by uv.spawn. Provided vars take precedence.
---@param env table<string, string>
---@return string[]
local function build_env(env)
  local result = {}
  for k, v in pairs(vim.tbl_extend("keep", env, vim.fn.environ())) do
    if k:find("^[^=]*$") then result[#result + 1] = k .. "=" .. tostring(v) end
  end
  return result
end

---@param params easy-dotnet.Job.TrackedJob
return function(params, response, throw, validate)
  local state = get_state()

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

  if state.is_running then
    throw({ code = -32000, message = "A job is already running in the terminal" })
    return
  end

  local opts = require("easy-dotnet.options").get_option("external_terminal")

  local full_args = {}
  vim.list_extend(full_args, opts.args or {})
  vim.list_extend(full_args, { command.executable })
  vim.list_extend(full_args, command.arguments or {})

  local handle

  handle = vim.uv.spawn(opts.command, {
    args = full_args,
    detached = true,
    cwd = (command.workingDirectory and command.workingDirectory ~= "") and command.workingDirectory or nil,
    env = command.environmentVariables and build_env(command.environmentVariables) or nil,
  }, function(_)
    if handle then handle:close() end
  end)

  if not handle then
    throw({ code = -32000, message = "Failed to launch external terminal: " .. opts.command })
    return
  end

  state.is_running = true
  response({})
end
