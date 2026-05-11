-- Renders EF Core CommandExecuted virtual text on the line that issued each query.
-- The server sends only the buckets whose counters changed since the last flush, keyed by a
-- stable bucketId — we merge incoming buckets into our cache, never replace it wholesale.
local M = {}

local ns = vim.api.nvim_create_namespace("easy_dotnet_profiler_sql")

---@class easy-dotnet.ProfilerSqlBucket
---@field bucketId string
---@field file string
---@field line integer
---@field sqlSample string
---@field parametersSample string?
---@field count integer
---@field totalMs integer
---@field maxMs integer

---All buckets keyed by their stable server-side bucketId.
---@type table<string, easy-dotnet.ProfilerSqlBucket>
M.by_id = {}

---Derived view: bucket per (normalized_file, line). Last-write-wins when multiple buckets
---share a line (e.g. different query shapes from the same call site) — the rendered virtual
---text reflects whichever bucket changed most recently.
---@type table<string, table<integer, easy-dotnet.ProfilerSqlBucket>>
M.buckets = {}

---Buckets whose call site couldn't be correlated to user code. Server-side filtering normally
---drops these before they reach us, but keep the bin in case some slip through.
---@type easy-dotnet.ProfilerSqlBucket[]
M.unknown = {}

local function normalize(path) return vim.fs.normalize(path) end

local function format_ms(ms)
  if ms < 1000 then return string.format("%dms", ms) end
  return string.format("%.2fs", ms / 1000)
end

local function buffers_for(file)
  local target = normalize(file)
  local matches = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and normalize(name) == target then table.insert(matches, buf) end
    end
  end
  return matches
end

local function render_file(file)
  local lines = M.buckets[file]
  if not lines then return end
  for _, buf in ipairs(buffers_for(file)) do
    pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(buf)
    for line, bucket in pairs(lines) do
      local row = line - 1
      if row >= 0 and row < line_count then
        local avg = bucket.count > 0 and (bucket.totalMs / bucket.count) or 0
        local label = string.format("  🔎 %dx · p̄ %s · max %s", bucket.count, format_ms(math.floor(avg + 0.5)), format_ms(bucket.maxMs))
        local hl = "DiagnosticHint"
        if bucket.maxMs >= 200 then
          hl = "DiagnosticError"
        elseif bucket.maxMs >= 50 then
          hl = "DiagnosticWarn"
        end
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
          virt_text = { { label, hl } },
          virt_text_pos = "eol",
          hl_mode = "combine",
        })
      end
    end
  end
end

---Merge server-sent SQL buckets into the cache. The server sends only changed buckets keyed
---by a stable bucketId, so each delivery is incremental — existing buckets whose counters
---haven't moved aren't re-sent and must not be cleared.
---@param buckets easy-dotnet.ProfilerSqlBucket[]
function M.apply_buckets(buckets)
  if not buckets then return end

  local touched = {}
  for _, b in ipairs(buckets) do
    if not b.bucketId then
      -- Defensive: older server might not stamp ids.
    elseif b.file == "<unknown>" or not b.line or b.line <= 0 then
      M.by_id[b.bucketId] = b
      table.insert(M.unknown, b)
    else
      M.by_id[b.bucketId] = b
      local file = normalize(b.file)
      M.buckets[file] = M.buckets[file] or {}
      M.buckets[file][b.line] = b
      touched[file] = true
    end
  end

  for file, _ in pairs(touched) do
    render_file(file)
  end
end

function M.clear()
  M.by_id = {}
  M.buckets = {}
  M.unknown = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1) end
  end
end

---Render any cached buckets onto a buffer when it's (re)loaded/displayed.
---@param bufnr integer
function M.refresh_buffer(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return end
  local file = normalize(name)
  if M.buckets[file] then render_file(file) end
end

---Returns the bucket at the cursor position, or nil if none.
---@return easy-dotnet.ProfilerSqlBucket?
local function bucket_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then return nil end
  local file = normalize(name)
  local lines = M.buckets[file]
  if not lines then return nil end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return lines[row]
end

---Show full SQL + parameters for the bucket on the current line in a floating window.
---Bind this to a key if you want one-keystroke access:
---   vim.keymap.set('n', '<leader>ds', function() require('easy-dotnet.profiler.sql').show_hover() end)
function M.show_hover()
  local bucket = bucket_at_cursor()
  if not bucket then
    vim.notify("No SQL bucket on this line", vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format(
      "count: %d   total: %s   max: %s   avg: %s",
      bucket.count,
      format_ms(bucket.totalMs),
      format_ms(bucket.maxMs),
      format_ms(math.floor((bucket.totalMs / math.max(bucket.count, 1)) + 0.5))
    ),
    "",
    "─ SQL ─",
  }
  for s in (bucket.sqlSample or ""):gmatch("[^\n]+") do
    table.insert(lines, s)
  end
  if bucket.parametersSample and bucket.parametersSample ~= "" then
    table.insert(lines, "")
    table.insert(lines, "─ Parameters (most recent) ─")
    for s in bucket.parametersSample:gmatch("[^\n]+") do
      table.insert(lines, s)
    end
  end

  local width = 0
  for _, l in ipairs(lines) do
    if #l > width then width = #l end
  end
  width = math.min(width + 2, math.floor(vim.o.columns * 0.9))
  local height = math.min(#lines, math.floor(vim.o.lines * 0.5))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sql"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " EF Core query ",
    title_pos = "left",
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufLeave", "InsertEnter" }, {
    once = true,
    callback = function() pcall(vim.api.nvim_win_close, win, true) end,
  })
end

---Open a buffer listing buckets whose call site couldn't be resolved. Useful for diagnosing
---queries issued from non-managed paths or so fast no sample landed on the calling thread.
function M.show_unknown()
  if #M.unknown == 0 then
    vim.notify("No unattributed SQL buckets", vim.log.levels.INFO)
    return
  end
  local lines = { string.format("# Unattributed EF Core queries (%d)", #M.unknown), "" }
  local sorted = vim.deepcopy(M.unknown)
  table.sort(sorted, function(a, b) return (a.totalMs or 0) > (b.totalMs or 0) end)
  for _, b in ipairs(sorted) do
    table.insert(lines, string.format("## count=%d  total=%s  max=%s", b.count, format_ms(b.totalMs), format_ms(b.maxMs)))
    for s in (b.sqlSample or ""):gmatch("[^\n]+") do
      table.insert(lines, "    " .. s)
    end
    table.insert(lines, "")
  end
  vim.cmd("new")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].modifiable = false
end

return M
