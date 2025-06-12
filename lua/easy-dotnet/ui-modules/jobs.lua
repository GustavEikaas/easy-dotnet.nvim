---@class JobData
---@field name string The job description text (e.g., "building...")
---@field on_success_text? string Text shown if the job succeeds
---@field on_error_text? string Text shown if the job fails

---@alias JobEventType "started" | "finished"

---@class JobEvent
---@field event JobEventType The type of job event.
---@field job JobData The job identifier or description.
---@field success? boolean Whether the job was successful (only for "finished" events).
---@field result? JobResult

---@class JobResult
---@field msg string The result text of the job
---@field level vim.log.levels The log level of the result
---@field stack_trace? string[]

---@class JobTracker
---@field jobs JobData[] List of current jobs.
---@field job_counter integer Job ID counter.
---@field spinner_counter integer Spinner frame counter.
---@field MAX_DESC_LEN integer Max length of job description.
---@field spinner_frames string[] Spinner animation frames.
---@field listeners JobLifecycleListener[]
---@field register_job fun(job: JobData): fun(success: boolean, error?: string[]) Adds a job and returns a function to remove it.
---@field register_listener fun(listener: JobLifecycleListener): fun() Registers a listener and returns a function to remove it.
---@field notify_listeners fun(event: JobEvent): (fun(event: JobEvent)?)[] Calls all registered listeners with a job event and returns their optional finish callbacks.
---@field lualine fun(): string Returns a string representing current job state, intended for statusline display.

--- A listener receives a JobEvent on "started"
--- and returns a function that will be called with a JobEvent on "finished"
---@alias JobLifecycleListener fun(event: JobEvent): fun(event: JobEvent)?

---@type JobTracker
---@diagnostic disable-next-line: missing-fields
local M = {
  jobs = {},
  job_counter = 1,
  spinner_counter = 0,
  MAX_DESC_LEN = 36,
  spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  listeners = {},
  finished_job = nil,
}

---Register a job and get a function to remove it
---@param job JobData The job description
---@return fun(success: boolean, error?: string[]) remove_callback
function M.register_job(job)
  local index = #M.jobs + 1
  M.jobs[index] = job
  local on_finished = M.notify_listeners({ event = "started", job = job })

  return function(success, error)
    M.jobs = vim.tbl_filter(function(x) return x ~= job end, M.jobs)
    local is_error = success == false
    local msg = is_error and (job.on_error_text or job.name) or (job.on_success_text or job.name)
    local level = is_error and vim.log.levels.ERROR or vim.log.levels.INFO
    M.finished_job = msg
    M.job_counter = M.job_counter + 1
    for _, value in ipairs(on_finished) do
      value({ event = "finished", success = success, job = job, result = { msg = msg, level = level, stack_trace = error } })
    end
  end
end

---Register a job lifecycle listener
---@param listener JobLifecycleListener
---@return fun() remove_callback
function M.register_listener(listener)
  table.insert(M.listeners, listener)

  return function()
    M.listeners = vim.tbl_filter(function(l) return l ~= listener end, M.listeners)
  end
end

function M.notify_listeners(event)
  return vim.iter(M.listeners):map(function(listener) return listener(event) end):totable()
end

function M.lualine()
  local total_jobs = #M.jobs
  if total_jobs == 0 then return M.finished_job or "" end

  M.job_counter = (M.job_counter % total_jobs) + 1
  M.spinner_counter = (M.spinner_counter % #M.spinner_frames) + 1
  local spinner_frame = M.spinner_frames[M.spinner_counter]

  local job_obj = M.jobs[M.job_counter]
  local job_desc = job_obj and job_obj.name or ""
  if #job_desc > M.MAX_DESC_LEN then job_desc = job_desc:sub(1, M.MAX_DESC_LEN - 3) .. "..." end
  if total_jobs > 1 then
    return string.format("%s (%d/%d) %s", spinner_frame, M.job_counter, total_jobs, job_desc)
  else
    return string.format("%s %s", spinner_frame, job_desc)
  end
end

return M
