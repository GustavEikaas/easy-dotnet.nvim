---@class easy-dotnet.UpgradeCandidate
---@field packageId string
---@field currentVersion string
---@field latestSafeVersion string
---@field latestVersion string
---@field upgradeSeverity "Major"|"Minor"|"Patch"
---@field affectedProjects string[]
---@field isCentrallyManaged boolean

---@class easy-dotnet.UpgradeWizardStatus
---@field phase "Idle"|"Analyzing"|"Applying"|"Done"|"Failed"
---@field message string|nil

---@class easy-dotnet.UpgradeProgress
---@field packageId string
---@field current integer
---@field total integer
---@field success boolean
---@field error string|nil

---@class easy-dotnet.UpgradeResultItem
---@field packageId string
---@field fromVersion string
---@field toVersion string
---@field error string|nil

---@class easy-dotnet.UpgradeResult
---@field updated easy-dotnet.UpgradeResultItem[]
---@field failed easy-dotnet.UpgradeResultItem[]

---@class easy-dotnet.ChangelogResult
---@field packageId string
---@field version string
---@field body string|nil
---@field source "github"|"nuspec"|"none"
---@field gitHubReleaseUrl string|nil
---@field projectUrl string|nil
---@field nugetUrl string

local M = {}

-- Server-pushed state
---@type easy-dotnet.UpgradeCandidate[]
M.candidates = {}

---@type easy-dotnet.UpgradeWizardStatus
M.status = { phase = "Idle", message = nil }

---@type easy-dotnet.UpgradeProgress|nil
M.progress = nil

---@type easy-dotnet.UpgradeResult|nil
M.result = nil

-- UI-only state (never sent to server)

---@type table<string, boolean>  packageId → selected
M.selection = {}

---@type "safe"|"latest"
M.mode = "safe"

---@type table<string, easy-dotnet.ChangelogResult>  key = packageId.."|"..version
M.changelog_cache = {}

---@type string|nil  packageId of the package whose changelog is shown
M.focused_pkg = nil

---@type string|nil  packageId of the failed package whose error is shown
M.focused_error_pkg = nil

--- Set initial mode and pre-select candidates (called after initialized notification).
function M.auto_select_safe()
  M.selection = {}
  local has_safe = false
  for _, c in ipairs(M.candidates) do
    if c.upgradeSeverity ~= "Major" then has_safe = true; break end
  end
  -- If everything is a major bump, default to latest so the list isn't empty
  M.mode = has_safe and "safe" or "latest"
  for _, c in ipairs(M.candidates) do
    if c.upgradeSeverity ~= "Major" then M.selection[c.packageId] = true end
  end
end

---@type table<string, string>  packageId → user-pinned version override
M.version_overrides = {}

---@type string|nil  solution/project path used to open the wizard (for apply)
M.target_path = nil

--- Reset all mutable state (called when wizard opens fresh).
function M.reset()
  M.candidates = {}
  M.status = { phase = "Idle", message = nil }
  M.progress = nil
  M.result = nil
  M.selection = {}
  M.mode = "safe"
  M.changelog_cache = {}
  M.focused_pkg = nil
  M.focused_error_pkg = nil
  M.version_overrides = {}
  M.target_path = nil
end

return M
