---@class easy-dotnet.RunningSession
---@field projects string[] Names of currently running projects

---@type easy-dotnet.RunningSession
local M = {
  projects = {},
}

---@param params { projects: string[] } | nil
function M.set(params) M.projects = params and params.projects or {} end

---@return boolean
function M.is_running() return #M.projects > 0 end

--- Lualine component: shows "■ name" when running, empty string when idle.
---@return string
function M.lualine()
  if #M.projects == 0 then return "" end
  return "■ " .. table.concat(M.projects, ", ")
end

--- Combined lualine component that merges active project + run/stop affordance.
---
--- • Idle:    "ProjectName ▶ "   (left-click = run, right-click = debug)
--- • Running: "■ ProjectName"    (any click = stop)
---
--- Usage:
---   { require("easy-dotnet").lualine.run_status, on_click = require("easy-dotnet").lualine.run_status_click }
---@return string
function M.run_status()
  local active = require("easy-dotnet.active-project")
  if #M.projects > 0 then return "■ " .. table.concat(M.projects, ", ") end
  local name = active.lualine()
  if name == "" then return "" end
  return " ▶ " .. name
end

--- on_click handler for the run_status component.
--- Left-click: run (idle) / stop (running). Right-click: debug (idle).
---@param _clicks integer
---@param button string "l" | "r" | "m"
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
