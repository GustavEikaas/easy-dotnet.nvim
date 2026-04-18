local ns_id = vim.api.nvim_create_namespace("easy_dotnet_upgrade_wizard")

local M = {
  buf = nil,
  win = nil,
}

local line_to_pkg = {}

local ICON_CHECKED   = "󰄲"
local ICON_UNCHECKED = "󰄱"

local severity_hl = {
  Major = "DiagnosticError",
  Minor = "DiagnosticWarn",
  Patch = "DiagnosticHint",
}

local phase_hl = {
  Analyzing = "DiagnosticWarn",
  Applying  = "DiagnosticWarn",
  Done      = "DiagnosticOk",
  Failed    = "DiagnosticError",
  Idle      = "Comment",
}

local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }
local spinner_timer = nil
local spinner_frame = 1
local _writing = false

local function start_spinner()
  if spinner_timer then return end
  spinner_timer = vim.uv.new_timer()
  spinner_timer:start(0, 80, vim.schedule_wrap(function()
    spinner_frame = (spinner_frame % #spinner_frames) + 1
    M.refresh()
  end))
end

local function stop_spinner()
  if not spinner_timer then return end
  spinner_timer:stop()
  spinner_timer:close()
  spinner_timer = nil
end

local function rpad(s, width)
  local dw = vim.fn.strdisplaywidth(s)
  if dw >= width then return s end
  return s .. string.rep(" ", width - dw)
end

local function set_line(lines, hls, text, hl)
  local lnum = #lines + 1
  table.insert(lines, text)
  if hl then table.insert(hls, { lnum - 1, 0, -1, hl }) end
  return lnum
end

---@return easy-dotnet.UpgradeCandidate|nil
function M.pkg_at_cursor()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return nil end
  local state = require("easy-dotnet.package-upgrade.state")
  local row = vim.api.nvim_win_get_cursor(M.win)[1]
  local pkg_id = line_to_pkg[row]
  if not pkg_id then return nil end
  for _, c in ipairs(state.candidates) do
    if c.packageId == pkg_id then return c end
  end
  return nil
end

function M.refresh()
  if _writing then return end
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  local state = require("easy-dotnet.package-upgrade.state")

  local lines = {}
  local hls   = {}
  line_to_pkg = {}

  local phase   = state.status.phase
  local spinning = phase == "Analyzing" or phase == "Applying"
  local count    = #state.candidates

  local col_id  = 10
  local col_ver = 8
  for _, c in ipairs(state.candidates) do
    if c.upgradeSeverity == "Major" and state.mode == "safe" then goto skip end
    col_id  = math.max(col_id,  vim.fn.strdisplaywidth(c.packageId))
    col_ver = math.max(col_ver, vim.fn.strdisplaywidth(c.currentVersion))
    ::skip::
  end
  col_id  = math.min(col_id + 2, 55)
  col_ver = col_ver + 2

  local spin_icon  = spinning and (spinner_frames[spinner_frame] .. "  ") or ""
  local mode_label = state.mode == "safe" and "safe" or "latest"
  local selected_n = 0
  for _ in pairs(state.selection) do selected_n = selected_n + 1 end

  local n_major, n_minor, n_patch = 0, 0, 0
  for _, c in ipairs(state.candidates) do
    if     c.upgradeSeverity == "Major" then n_major = n_major + 1
    elseif c.upgradeSeverity == "Minor" then n_minor = n_minor + 1
    else                                      n_patch = n_patch + 1
    end
  end

  local left
  if phase == "Applying" and state.progress then
    local p       = state.progress
    local pct     = p.total > 0 and math.floor(p.current / p.total * 100) or 0
    local bar_w   = 18
    local filled  = math.floor(bar_w * pct / 100)
    local bar     = string.rep("█", filled) .. string.rep("░", bar_w - filled)
    left = string.format("  󰏖  NuGet Upgrade Wizard    %s%s  [%s] %3d%%  %s",
      spin_icon, phase, bar, pct, p.packageId or "")
  else
    left = string.format("  󰏖  NuGet Upgrade Wizard    mode: %s    %s%s    %d/%d selected",
      mode_label, spin_icon, phase, selected_n, count)
  end

  local win_width = (M.win and vim.api.nvim_win_is_valid(M.win))
      and vim.api.nvim_win_get_width(M.win) or 90

  local right_parts = {}
  if state.result then
    local ok_n  = #state.result.updated
    local err_n = #state.result.failed
    table.insert(right_parts, { string.format("  󰄬 %d upgraded", ok_n), "DiagnosticOk" })
    if err_n > 0 then
      table.insert(right_parts, { string.format("  󰅖 %d failed", err_n), "DiagnosticError" })
    end
    table.insert(right_parts, { "  ", nil })
  elseif count > 0 then
    if n_major > 0 then table.insert(right_parts, { string.format("  Major %d", n_major), "DiagnosticError" }) end
    if n_minor > 0 then table.insert(right_parts, { string.format("  Minor %d", n_minor), "DiagnosticWarn"  }) end
    if n_patch > 0 then table.insert(right_parts, { string.format("  Patch %d", n_patch), "DiagnosticHint"  }) end
    table.insert(right_parts, { "  ", nil })
  end

  local right_text = ""
  for _, part in ipairs(right_parts) do right_text = right_text .. part[1] end
  local left_dw  = vim.fn.strdisplaywidth(left)
  local right_dw = vim.fn.strdisplaywidth(right_text)
  local pad      = math.max(1, win_width - left_dw - right_dw)
  local header_line = left .. string.rep(" ", pad) .. right_text

  local header_row = #lines
  table.insert(lines, header_line)
  table.insert(hls, { header_row, 0, #left, phase_hl[phase] or "Normal" })
  local byte_col = #left + pad
  for _, part in ipairs(right_parts) do
    if part[2] then
      table.insert(hls, { header_row, byte_col, byte_col + #part[1], part[2] })
    end
    byte_col = byte_col + #part[1]
  end

  set_line(lines, hls, string.rep("─", 72), "Comment")

  if count > 0 then
    local heading = string.format("     %s  %s  %s  %s",
      rpad("Package", col_id), rpad("Current", col_ver), rpad("Target", col_ver), "Severity")
    set_line(lines, hls, heading, "Comment")
    set_line(lines, hls, string.rep("─", 72), "Comment")
  end

  local failed_map = {}
  if state.result then
    for _, item in ipairs(state.result.failed) do
      failed_map[item.packageId] = item.error or "restore failed"
    end
  end

  if count == 0 and phase == "Idle" then
    set_line(lines, hls, "  No outdated packages found.", "Comment")
  elseif count == 0 then
    set_line(lines, hls, "  Analyzing packages…", "Comment")
  else
    for _, c in ipairs(state.candidates) do
      if c.upgradeSeverity == "Major" and state.mode == "safe" then goto continue end

      local failed_err = failed_map[c.packageId]
      local icon, row_hl
      if failed_err then
        icon   = "󰅖"
        row_hl = "DiagnosticError"
      else
        icon   = state.selection[c.packageId] and ICON_CHECKED or ICON_UNCHECKED
        row_hl = severity_hl[c.upgradeSeverity]
      end

      local override  = state.version_overrides[c.packageId]
      local target    = override or (state.mode == "safe" and c.latestSafeVersion or c.latestVersion)
      local cpm       = c.isCentrallyManaged and " [CPM]" or ""
      local pin_hint  = override and " 󰐊" or ""
      local err_hint  = failed_err and "  !" or ""
      local line_text = string.format("  %s  %s  %s  %s  %s%s%s%s",
        icon,
        rpad(c.packageId,      col_id),
        rpad(c.currentVersion, col_ver),
        rpad(target,           col_ver),
        c.upgradeSeverity, cpm, pin_hint, err_hint)

      local lnum = set_line(lines, hls, line_text, row_hl)
      line_to_pkg[lnum] = c.packageId

      if override then
        local bp = 2 + 4 + 2 + col_id + 2 + col_ver + 2
        table.insert(hls, { lnum - 1, bp, bp + #target, "DiagnosticWarn" })
      end

      ::continue::
    end
  end

  if state.focused_error_pkg then
    local err_msg = failed_map[state.focused_error_pkg]
    set_line(lines, hls, "", nil)
    set_line(lines, hls, string.rep("─", 72), "Comment")
    set_line(lines, hls, string.format("  󰅖  Restore error: %s", state.focused_error_pkg), "DiagnosticError")
    set_line(lines, hls, "", nil)
    if err_msg then
      for _, eline in ipairs(vim.split(err_msg, "\n", { plain = true })) do
        set_line(lines, hls, "  " .. eline, "DiagnosticError")
      end
    end
  end

  local focused = state.focused_pkg
  if focused then
    local candidate = nil
    for _, c in ipairs(state.candidates) do
      if c.packageId == focused then candidate = c; break end
    end
    local version = candidate and (state.mode == "safe" and candidate.latestSafeVersion or candidate.latestVersion) or ""
    local key = focused .. "|" .. version
    local cl  = state.changelog_cache[key]

    set_line(lines, hls, "", nil)
    set_line(lines, hls, string.rep("─", 72), "Comment")

    if cl == nil or (cl.source == "none" and cl.body == nil) then
      local loading = cl == nil or (cl.source == "none" and cl.nugetUrl == "")
      if loading then
        set_line(lines, hls, string.format("  󰇚  %s %s  loading…", focused, version), "Comment")
      else
        set_line(lines, hls, string.format("  󰌍  %s %s  no changelog found", focused, version), "Comment")
        if cl and cl.nugetUrl and cl.nugetUrl ~= "" then
          set_line(lines, hls, "       " .. cl.nugetUrl, "Underlined")
        end
      end
    else
      local src_badge = cl.source == "github" and "  GitHub" or "  nuspec"
      set_line(lines, hls, string.format("  󰌍  %s %s%s", focused, version, src_badge), "Title")
      if cl.gitHubReleaseUrl then set_line(lines, hls, "       " .. cl.gitHubReleaseUrl, "Underlined") end
      set_line(lines, hls, "", nil)
      if cl.body then
        for _, body_line in ipairs(vim.split(cl.body, "\n", { plain = true })) do
          set_line(lines, hls, "  " .. body_line, nil)
        end
      end
    end
  end

  set_line(lines, hls, "", nil)
  set_line(lines, hls, string.rep("─", 72), "Comment")
  set_line(lines, hls,
    "  <Space> toggle  a safe-all  A all  X clear  u apply  v pin-ver  K changelog  e errors  m mode  q quit",
    "Comment")

  _writing = true
  local ok, err = pcall(function()
    vim.bo[M.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    vim.bo[M.buf].modifiable = false
  end)
  _writing = false

  if not ok then
    require("easy-dotnet.logger").debug("upgrade-wizard render error: " .. tostring(err))
    return
  end

  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  for _, hl in ipairs(hls) do
    local row0, cs, ce, group = hl[1], hl[2], hl[3], hl[4]
    if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
      vim.hl.range(M.buf, ns_id, group, { row0, cs }, { row0, ce })
    end
  end

  if spinning then start_spinner() else stop_spinner() end
end

function M.open()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_delete(M.buf, { force = true })
  end

  M.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden  = "wipe"
  vim.bo[M.buf].filetype   = "easy-dotnet-upgrade-wizard"
  vim.bo[M.buf].modifiable = false

  local ui     = vim.api.nvim_list_uis()[1]
  local width  = math.max(90, math.floor((ui and ui.width  or 130) * 0.8))
  local height = math.max(20, math.floor((ui and ui.height or 40)  * 0.75))
  local row    = math.floor(((ui and ui.height or 40)  - height) / 2)
  local col    = math.floor(((ui and ui.width  or 130) - width)  / 2)

  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative  = "editor",
    width     = width,
    height    = height,
    row       = row,
    col       = col,
    style     = "minimal",
    border    = "rounded",
    title     = "  NuGet Upgrade Wizard ",
    title_pos = "center",
  })
  vim.wo[M.win].wrap       = false
  vim.wo[M.win].cursorline = true

  M.refresh()
end

function M.hide()
  stop_spinner()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
  M.buf = nil
end

return M

