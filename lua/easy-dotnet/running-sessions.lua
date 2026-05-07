---@class easy-dotnet.RunningSessionInfo
---@field name string
---@field isDebugging boolean

---@class easy-dotnet.RunningSessionState
---@field projects easy-dotnet.RunningSessionInfo[]

-- Codicons: debug_start (idle), debug_stop (running), debug (debugging)
local ICON_IDLE = "" -- nf-cod-debug_start
local ICON_RUNNING = "" -- nf-cod-debug_stop
local ICON_DEBUG = "" -- nf-cod-debug

local COLOR_RUNNING = { fg = "#1e1e2e", bg = "#a6e3a1", bold = true } -- green badge
local COLOR_DEBUG = { fg = "#1e1e2e", bg = "#fab387", bold = true } -- orange badge

---@type easy-dotnet.RunningSessionState
local M = {
  projects = {},
}

---@param params { projects: easy-dotnet.RunningSessionInfo[] } | nil
function M.set(params) M.projects = params and params.projects or {} end

---@return boolean
function M.is_running() return #M.projects > 0 end

--- Returns the dominant state across all running sessions.
--- Priority: debugging > running > idle.
---@return "idle"|"running"|"debugging"
local function state()
  if #M.projects == 0 then return "idle" end
  for _, s in ipairs(M.projects) do
    if s.isDebugging then return "debugging" end
  end
  return "running"
end

--- Lualine color function — returns a badge color table when active, nil when idle.
---@return { fg: string, bg: string, bold: boolean }|nil
function M.run_status_color()
  local s = state()
  if s == "debugging" then return COLOR_DEBUG end
  if s == "running" then return COLOR_RUNNING end
  return nil
end

--- Combined lualine component: idle shows the active project with a start icon;
--- running/debugging shows each session with a stop/debug icon.
---
--- State → appearance:
---   idle:      " ProjectName"   normal fg  (L-click = run, R-click = debug)
---   running:   " ProjectName"   green      (any click = stop)
---   debugging: " ProjectName"   orange     (any click = stop)
---
--- Usage:
---   {
---     require("easy-dotnet").lualine.run_status,
---     color  = require("easy-dotnet").lualine.run_status_color,
---     on_click = require("easy-dotnet").lualine.run_status_click,
---   }
---@return string
function M.run_status()
  if #M.projects > 0 then
    local parts = vim.tbl_map(function(s) return (s.isDebugging and ICON_DEBUG or ICON_RUNNING) .. " " .. s.name end, M.projects)
    return table.concat(parts, "  ")
  end
  local name = require("easy-dotnet.active-project").lualine()
  if name == "" then return "" end
  return ICON_IDLE .. " " .. name
end

--- on_click handler for the run_status component.
--- L-click: run (idle) or stop (running). R-click: debug (idle).
---@param _clicks integer
---@param button string "l"|"r"|"m"
function M.run_status_click(_clicks, button)
  local dotnet = require("easy-dotnet")
  if #M.projects > 0 then
    dotnet.stop()
  elseif button == "r" then
    dotnet.debug_profile_default()
  else
    dotnet.run_profile_default()
  end
end

return M
