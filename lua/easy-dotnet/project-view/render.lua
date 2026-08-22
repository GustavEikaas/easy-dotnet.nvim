local state = require("easy-dotnet.project-view.state")

local ns = vim.api.nvim_create_namespace("easy_dotnet_project_view")
local ns_footer = vim.api.nvim_create_namespace("easy_dotnet_project_view_footer")

local M = {
  buf = nil,
  win = nil,
  footer_buf = nil,
  footer_win = nil,
  options = {},
  rows = {},
}

local icons = {
  project = "󰘐",
  package = "",
  version = "",
  reference = "",
  outdated = "",
}

local hl = {
  title = "EasyDotnetProjectViewTitle",
  section = "EasyDotnetProjectViewSection",
  count = "EasyDotnetProjectViewCount",
  package = "EasyDotnetProjectViewPackage",
  version = "EasyDotnetProjectViewVersion",
  ref = "EasyDotnetProjectViewProjectRef",
  meta = "EasyDotnetProjectViewMeta",
  outdated = "EasyDotnetProjectViewOutdated",
  empty = "EasyDotnetProjectViewEmpty",
  key = "EasyDotnetProjectViewKey",
  major = "EasyDotnetProjectViewUpgradeMajor",
  minor = "EasyDotnetProjectViewUpgradeMinor",
  patch = "EasyDotnetProjectViewUpgradePatch",
}

local function severity_hl(severity)
  local s = (severity or ""):lower()
  if s == "major" then
    return hl.major
  elseif s == "minor" then
    return hl.minor
  elseif s == "patch" then
    return hl.patch
  end
  return hl.version
end

local spinner = {
  frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
  timer = nil,
  frame = 1,
  interval = 80,
}

local function get_dims(content_height)
  local width = math.min(math.floor(vim.o.columns * 0.7), 90)
  width = math.max(width, 50)
  local max_height = math.floor(vim.o.lines * 0.7)
  local height = math.max(8, math.min(content_height, max_height))
  local col = math.floor((vim.o.columns - width) / 2)
  local total = height + 2 + 3
  local row = math.max(1, math.floor((vim.o.lines - total) / 2))
  return {
    width = width,
    height = height,
    col = col,
    row = row,
    footer_row = row + height + 2,
  }
end

local function pad_right(left_text, right_text, right_hls, win_width)
  local left_dw = vim.fn.strdisplaywidth(left_text)
  local right_dw = vim.fn.strdisplaywidth(right_text)
  if left_dw + right_dw + 2 > win_width then return left_text, {} end
  local pad = win_width - left_dw - right_dw - 1
  local offset = #left_text + pad
  local line = left_text .. string.rep(" ", pad) .. right_text
  local shifted = {}
  for _, h in ipairs(right_hls) do
    table.insert(shifted, { h[1] + offset, h[2] + offset, h[3] })
  end
  return line, shifted
end

local function build_meta_line()
  local header = state.snapshot and state.snapshot.header
  if not header then return " ", {} end

  local parts = {}
  if header.targetFrameworks and #header.targetFrameworks > 0 then table.insert(parts, table.concat(header.targetFrameworks, " / ")) end
  if header.version and header.version ~= "" then table.insert(parts, "v" .. header.version) end
  if header.langVersion and header.langVersion ~= "" then table.insert(parts, header.langVersion) end
  if header.outputType and header.outputType ~= "" then table.insert(parts, header.outputType) end

  local text = "  " .. table.concat(parts, "   ·   ")
  return text, { { 0, #text, hl.meta } }
end

---@param row easy-dotnet.ProjectView.Row
---@param win_width integer
local function build_line(row, win_width)
  if row.kind == "meta" then return build_meta_line() end
  if row.kind == "none" then return "", {} end

  if row.kind == "section" then
    local icon = row.section == "packages" and icons.package or icons.reference
    local left = string.format(" %s %s", icon, row.label)
    local count = string.format("(%d)", row.count or 0)
    local text = left .. "  " .. count
    local hls = {
      { 0, #left, hl.section },
      { #left + 2, #text, hl.count },
    }
    return text, hls
  end

  if row.kind == "empty" then
    local text = "     none"
    return text, { { 0, #text, hl.empty } }
  end

  if row.kind == "package" then
    local pkg = row.pkg
    local left = string.format("    %s %s", icons.package, pkg.id)
    local left_hls = { { 4, 4 + #icons.package, hl.package }, { 4 + #icons.package + 1, #left, "Normal" } }

    local right, right_hls
    if pkg.isOutdated and pkg.latestVersion then
      local sev = severity_hl(pkg.upgradeSeverity)
      local arrow = "  →  "
      local cur = pkg.version
      right = cur .. arrow .. pkg.latestVersion
      right_hls = {
        { 0, #cur, hl.version },
        { #cur, #cur + #arrow, hl.meta },
        { #cur + #arrow, #right, sev },
      }
      local tag = pkg.upgradeSeverity
      if tag and tag ~= "" and tag ~= "None" and tag ~= "Unknown" then
        local pre = #right + 3
        right = right .. "   " .. tag:lower()
        table.insert(right_hls, { pre, #right, sev })
      end
    else
      right = string.format("%s %s", icons.version, pkg.version)
      right_hls = { { 0, #right, hl.version } }
    end

    local line, shifted = pad_right(left, right, right_hls, win_width)
    for _, h in ipairs(left_hls) do
      table.insert(shifted, h)
    end
    return line, shifted
  end

  if row.kind == "projectref" then
    local ref = row.ref
    local text = string.format("    %s %s", icons.reference, ref.name)
    return text, { { 4, 4 + #icons.reference, hl.ref }, { 4 + #icons.reference + 1, #text, "Normal" } }
  end

  return "", {}
end

local function any_outdated()
  local snap = state.snapshot
  if not snap then return false end
  for _, p in ipairs(snap.packages) do
    if p.isOutdated and p.latestVersion then return true end
  end
  return false
end

local function footer_groups(row)
  local groups = {}
  if row then
    if row.section == "packages" and (row.kind == "section" or row.kind == "empty") then
      groups = { { "a", "Add package" } }
    elseif row.section == "projectrefs" and (row.kind == "section" or row.kind == "empty") then
      groups = { { "a", "Add reference" } }
    elseif row.kind == "package" then
      local has_upgrade = row.pkg.isOutdated and row.pkg.latestVersion
      groups = { { "u", has_upgrade and "Accept" or "Update" }, { "x", "Remove" }, { "b", "Browse" } }
    elseif row.kind == "projectref" then
      groups = { { "x", "Remove" } }
    end
  end
  table.insert(groups, { "o", "Outdated" })
  if any_outdated() then table.insert(groups, { "U", "Upgrade all" }) end
  table.insert(groups, { "r", "Refresh" })
  table.insert(groups, { "q", "Close" })
  return groups
end

local function render_footer(frame)
  if not M.footer_buf or not vim.api.nvim_buf_is_valid(M.footer_buf) then return end

  local text, hls
  if state.loading then
    local f = frame or spinner.frames[spinner.frame]
    local op = state.operation or "Working…"
    text = string.format(" %s %s", f, op)
    hls = { { 0, #text, hl.outdated } }
  else
    local row = M.row_at_cursor()
    local groups = footer_groups(row)
    text = " "
    hls = {}
    for i, g in ipairs(groups) do
      if i > 1 then
        local sep = "   "
        text = text .. sep
      end
      local key, label = g[1], g[2]
      table.insert(hls, { #text, #text + #key, hl.key })
      text = text .. key .. " "
      table.insert(hls, { #text, #text + #label, "Comment" })
      text = text .. label
    end
  end

  vim.api.nvim_buf_clear_namespace(M.footer_buf, ns_footer, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.footer_buf })
  vim.api.nvim_buf_set_lines(M.footer_buf, 0, -1, false, { text })
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.footer_buf })
  for _, h in ipairs(hls) do
    vim.hl.range(M.footer_buf, ns_footer, h[3], { 0, h[1] }, { 0, h[2] })
  end
end

local function build_title(frame)
  local header = state.snapshot and state.snapshot.header
  local name = header and header.name or "Project"
  local title = string.format(" %s %s ", icons.project, name)
  if state.loading then title = string.format(" %s %s %s ", icons.project, name, frame or spinner.frames[spinner.frame]) end
  return title
end

local function update_title(frame)
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  pcall(vim.api.nvim_win_set_config, M.win, {
    title = build_title(frame),
    title_pos = "center",
  })
end

local function spinner_stop()
  if not spinner.timer then return end
  spinner.timer:stop()
  spinner.timer:close()
  spinner.timer = nil
end

local function spinner_tick()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then
    spinner_stop()
    return
  end
  spinner.frame = (spinner.frame % #spinner.frames) + 1
  update_title(spinner.frames[spinner.frame])
  render_footer(spinner.frames[spinner.frame])
end

local function spinner_start()
  if spinner.timer then return end
  spinner.frame = 1
  spinner.timer = vim.uv.new_timer()
  spinner.timer:start(0, spinner.interval, vim.schedule_wrap(spinner_tick))
end

---@return easy-dotnet.ProjectView.Row|nil
function M.row_at_cursor()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return nil end
  local line = vim.api.nvim_win_get_cursor(M.win)[1]
  return M.rows[line]
end

local function place_cursor_on_first_selectable()
  if not M.win or not vim.api.nvim_win_is_valid(M.win) then return end
  for i, row in ipairs(M.rows) do
    if row.selectable then
      pcall(vim.api.nvim_win_set_cursor, M.win, { i, 0 })
      return
    end
  end
end

function M.refresh()
  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then return end

  M.rows = state.build_rows()

  if state.loading then
    spinner_start()
    M.was_loading = true
  else
    spinner_stop()
    update_title()
    if M.was_loading then
      M.was_loading = false
      if M.win and vim.api.nvim_win_is_valid(M.win) and vim.api.nvim_get_current_win() ~= M.win then pcall(vim.api.nvim_set_current_win, M.win) end
    end
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    local dims = get_dims(#M.rows + 1)
    pcall(vim.api.nvim_win_set_config, M.win, { relative = "editor", width = dims.width, height = dims.height, col = dims.col, row = dims.row })
    if M.footer_win and vim.api.nvim_win_is_valid(M.footer_win) then
      pcall(vim.api.nvim_win_set_config, M.footer_win, { relative = "editor", width = dims.width, height = 1, col = dims.col, row = dims.footer_row })
    end
  end

  local win_width = (M.win and vim.api.nvim_win_is_valid(M.win)) and vim.api.nvim_win_get_width(M.win) or 80

  local lines = {}
  local highlights = {}
  for i, row in ipairs(M.rows) do
    local text, hls = build_line(row, win_width)
    lines[i] = text
    for _, h in ipairs(hls) do
      table.insert(highlights, { row = i - 1, h = h })
    end
  end

  vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
  vim.api.nvim_set_option_value("modifiable", true, { buf = M.buf })
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = M.buf })

  for _, item in ipairs(highlights) do
    local h = item.h
    vim.hl.range(M.buf, ns, h[3], { item.row, h[1] }, { item.row, h[2] })
  end

  render_footer()
end

function M.schedule_refresh()
  vim.schedule(function() M.refresh() end)
end

local function make_scratch_buf(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "easy-dotnet-project-view", { buf = buf })
  if name then pcall(vim.api.nvim_buf_set_name, buf, name) end
  return buf
end

local function disable_gutter(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = true
  pcall(vim.api.nvim_set_option_value, "statuscolumn", "", { win = win })
end

function M.open(options)
  M.options = options or M.options

  if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then M.buf = make_scratch_buf("Project View") end
  if not M.footer_buf or not vim.api.nvim_buf_is_valid(M.footer_buf) then M.footer_buf = make_scratch_buf() end

  local dims = get_dims(#state.build_rows() + 1)

  M.win = vim.api.nvim_open_win(M.buf, true, {
    relative = "editor",
    width = dims.width,
    height = dims.height,
    col = dims.col,
    row = dims.row,
    style = "minimal",
    border = "rounded",
    title = build_title(),
    title_pos = "center",
    focusable = true,
    zindex = 50,
  })
  disable_gutter(M.win)

  M.footer_win = vim.api.nvim_open_win(M.footer_buf, false, {
    relative = "editor",
    width = dims.width,
    height = 1,
    col = dims.col,
    row = dims.footer_row,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = 51,
  })
  vim.wo[M.footer_win].cursorline = false
  vim.wo[M.footer_win].winhighlight = "Normal:NormalFloat"

  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = M.buf,
    callback = function() render_footer() end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("EasyDotnetProjectViewResize", { clear = true }),
    callback = function() M.refresh() end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(M.win),
    once = true,
    callback = function()
      spinner_stop()
      if M.footer_win and vim.api.nvim_win_is_valid(M.footer_win) then pcall(vim.api.nvim_win_close, M.footer_win, true) end
      M.footer_win = nil
      M.win = nil
      pcall(vim.api.nvim_del_augroup_by_name, "EasyDotnetProjectViewResize")
    end,
  })

  M.refresh()
  place_cursor_on_first_selectable()
  render_footer()
end

function M.hide()
  spinner_stop()
  if M.footer_win and vim.api.nvim_win_is_valid(M.footer_win) then pcall(vim.api.nvim_win_close, M.footer_win, true) end
  M.footer_win = nil
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    pcall(vim.api.nvim_win_close, M.win, true)
    M.win = nil
  end
end

return M
