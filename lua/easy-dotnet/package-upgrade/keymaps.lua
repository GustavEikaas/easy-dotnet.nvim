local state  = require("easy-dotnet.package-upgrade.state")
local render = require("easy-dotnet.package-upgrade.render")
local logger = require("easy-dotnet.logger")

local M = {}

---@param buf integer
---@param client easy-dotnet.RPC.Client.Dotnet
---@param options easy-dotnet.PackageUpgrade.Options
function M.register(buf, client, options)
  local km = options.mappings or {}

  local function map(key, desc, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, desc = desc, noremap = true, silent = true })
  end

  map(km.toggle_selection and km.toggle_selection.lhs or "<Space>", "Toggle upgrade selection", function()
    local pkg = render.pkg_at_cursor()
    if not pkg then return end
    state.selection[pkg.packageId] = not state.selection[pkg.packageId] or nil
    render.refresh()
  end)

  map(km.select_all_safe and km.select_all_safe.lhs or "a", "Select all safe packages", function()
    for _, c in ipairs(state.candidates) do
      if c.upgradeSeverity ~= "Major" then state.selection[c.packageId] = true end
    end
    render.refresh()
  end)

  map(km.select_all and km.select_all.lhs or "A", "Select all packages", function()
    for _, c in ipairs(state.candidates) do
      state.selection[c.packageId] = true
    end
    render.refresh()
  end)

  map(km.clear_selection and km.clear_selection.lhs or "X", "Clear all selections", function()
    state.selection = {}
    render.refresh()
  end)

  map(km.apply and km.apply.lhs or "u", "Apply selected upgrades", function()
    local selections = {}
    for _, c in ipairs(state.candidates) do
      if state.selection[c.packageId] then
        local target = state.version_overrides[c.packageId]
            or (state.mode == "safe" and c.latestSafeVersion or c.latestVersion)
        table.insert(selections, {
          packageId          = c.packageId,
          targetVersion      = target,
          affectedProjects   = c.affectedProjects,
          isCentrallyManaged = c.isCentrallyManaged,
          currentVersion     = c.currentVersion,
        })
      end
    end
    if #selections == 0 then
      logger.warn("No packages selected for upgrade")
      return
    end
    client.upgrade_wizard:apply(state.target_path or "", selections, nil)
  end)

  map(km.errors and km.errors.lhs or "e", "Show restore error", function()
    local pkg = render.pkg_at_cursor()
    if not pkg or not state.result then return end
    local has_error = false
    for _, item in ipairs(state.result.failed) do
      if item.packageId == pkg.packageId then has_error = true; break end
    end
    if not has_error then return end
    if state.focused_error_pkg == pkg.packageId then
      state.focused_error_pkg = nil
    else
      state.focused_error_pkg = pkg.packageId
      state.focused_pkg = nil
    end
    render.refresh()
  end)

  map(km.changelog and km.changelog.lhs or "K", "Show changelog", function()
    local pkg = render.pkg_at_cursor()
    if not pkg then return end
    local target = state.mode == "safe" and pkg.latestSafeVersion or pkg.latestVersion
    local key    = pkg.packageId .. "|" .. target
    state.focused_pkg = pkg.packageId
    state.focused_error_pkg = nil
    if state.changelog_cache[key] then
      render.refresh()
      return
    end
    state.changelog_cache[key] = { packageId = pkg.packageId, version = target, body = nil, source = "none", nugetUrl = "" }
    render.refresh()
    client.upgrade_wizard:changelog(pkg.packageId, target, function(result)
      vim.schedule(function()
        if result then state.changelog_cache[key] = result end
        render.refresh()
      end)
    end)
  end)

  map(km.toggle_mode and km.toggle_mode.lhs or "m", "Toggle safe/latest mode", function()
    state.mode = state.mode == "safe" and "latest" or "safe"
    render.refresh()
  end)

  map(km.override_version and km.override_version.lhs or "v", "Pin specific version", function()
    local pkg = render.pkg_at_cursor()
    if not pkg then return end
    client.upgrade_wizard:versions(pkg.packageId, function(versions)
      vim.schedule(function()
        if not versions or #versions == 0 then
          logger.warn("No versions found for " .. pkg.packageId)
          return
        end
        vim.ui.select(versions, {
          prompt = "Pin version for " .. pkg.packageId .. ":",
        }, function(choice)
          if not choice then return end
          state.version_overrides[pkg.packageId] = choice
          -- Auto-select the package so the pinned version gets applied
          state.selection[pkg.packageId] = true
          render.refresh()
        end)
      end)
    end)
  end)

  map(km.close and km.close.lhs or "q",     "Close upgrade wizard", function() render.hide() end)
  map("<Esc>", "Close upgrade wizard", function() render.hide() end)
end

return M
