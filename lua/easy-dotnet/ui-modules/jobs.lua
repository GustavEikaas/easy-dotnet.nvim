local M = {
  jobs = {},
  job_counter = 1,
  spinner_counter = 0,
  MAX_DESC_LEN = 36,
  spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
}

---@param job string
---@return function remove_callback
function M.register_job(job)
  local index = #M.jobs + 1
  M.jobs[index] = job

  return function()
    local removed = vim.tbl_filter(function(x) return x ~= job end, M.jobs)
    M.jobs = removed

    M.job_counter = 1
  end
end

function M.get_state()
  local total_jobs = #M.jobs
  if total_jobs == 0 then return "" end

  M.job_counter = (M.job_counter % total_jobs) + 1
  M.spinner_counter = (M.spinner_counter % #M.spinner_frames) + 1
  local spinner_frame = M.spinner_frames[M.spinner_counter]

  local job_desc = M.jobs[M.job_counter] or ""
  if #job_desc > M.MAX_DESC_LEN then job_desc = job_desc:sub(1, M.MAX_DESC_LEN - 3) .. "..." end

  if total_jobs > 1 then
    return string.format("%s (%d/%d) %s", spinner_frame, M.job_counter, total_jobs, job_desc)
  else
    return string.format("%s %s", spinner_frame, job_desc)
  end
end

return M
