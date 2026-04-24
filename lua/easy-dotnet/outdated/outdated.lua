local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local constants = require("easy-dotnet.constants")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
local M = {}

---@alias easy-dotnet.PatternType "reference" | "version"

---@class easy-dotnet.Outdated.LineEntry
---@field pkg easy-dotnet.Nuget.OutdatedPackage
---@field extmark_id integer
---@field line integer

---@type table<integer, table<integer, easy-dotnet.Outdated.LineEntry>>
local buffer_state = {}

---@param package_name string # The name of the package to search for.
---@param pattern_type easy-dotnet.PatternType # The pattern type to use ("reference" or "version").
---@param bnr integer
---@return integer|nil # Returns the line number where the package is found, or nil if not found
local function find_package_in_buffer(package_name, pattern_type, bnr)
  -- Escape dots and hyphens in package name
  local escaped_package_name = package_name:gsub("[%.%-]", "%%%1")

  -- Define the pattern based on the type
  local pattern
  if pattern_type == "reference" then
    pattern = '<PackageReference Include="' .. escaped_package_name .. '"'
  elseif pattern_type == "version" then
    pattern = '<PackageVersion Include="' .. escaped_package_name .. '"'
  else
    error("Invalid pattern_type: " .. tostring(pattern_type))
    return nil
  end

  local num_lines = vim.api.nvim_buf_line_count(bnr)

  for line_number = 1, num_lines do
    local line = vim.api.nvim_buf_get_lines(bnr, line_number - 1, line_number, false)[1]
    if line and line:match(pattern) then return line_number end
  end

  return nil
end

---@param bnr integer
---@param line integer  # 1-indexed line number
---@param new_version string
---@return boolean # whether the line was modified
local function replace_version_on_line(bnr, line, new_version)
  local content = vim.api.nvim_buf_get_lines(bnr, line - 1, line, false)[1]
  if not content then return false end
  local replaced, count = content:gsub('(Version=")[^"]*(")', "%1" .. new_version .. "%2", 1)
  if count == 0 then return false end
  vim.api.nvim_buf_set_lines(bnr, line - 1, line, false, { replaced })
  return true
end

---@param bnr integer
---@param entry easy-dotnet.Outdated.LineEntry
local function upgrade_entry(bnr, entry)
  if replace_version_on_line(bnr, entry.line, entry.pkg.latestVersion) then
    pcall(vim.api.nvim_buf_del_extmark, bnr, constants.ns_id, entry.extmark_id)
    if buffer_state[bnr] then buffer_state[bnr][entry.line] = nil end
  else
    logger.warn("Could not find Version attribute for " .. entry.pkg.name)
  end
end

local function upgrade_under_cursor()
  local bnr = vim.api.nvim_get_current_buf()
  local state = buffer_state[bnr]
  if not state then return end
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local entry = state[cursor_line]
  if not entry then
    logger.warn("No outdated package on this line")
    return
  end
  upgrade_entry(bnr, entry)
end

local function upgrade_all()
  local bnr = vim.api.nvim_get_current_buf()
  local state = buffer_state[bnr]
  if not state then return end
  local entries = {}
  for _, entry in pairs(state) do
    table.insert(entries, entry)
  end
  table.sort(entries, function(a, b) return a.line > b.line end)
  for _, entry in ipairs(entries) do
    upgrade_entry(bnr, entry)
  end
end

---@param bnr integer
local function set_buffer_keymaps(bnr)
  local options = require("easy-dotnet.options").options
  local mappings = options.outdated and options.outdated.mappings or nil
  if not mappings then return end

  if mappings.upgrade and mappings.upgrade.lhs and mappings.upgrade.lhs ~= "" then
    vim.keymap.set("n", mappings.upgrade.lhs, upgrade_under_cursor, {
      buffer = bnr,
      silent = true,
      desc = mappings.upgrade.desc,
    })
  end

  if mappings.upgrade_all and mappings.upgrade_all.lhs and mappings.upgrade_all.lhs ~= "" then
    vim.keymap.set("n", mappings.upgrade_all.lhs, upgrade_all, {
      buffer = bnr,
      silent = true,
      desc = mappings.upgrade_all.desc,
    })
  end
end

---@param deps easy-dotnet.Nuget.OutdatedPackage[]
---@param pattern_type easy-dotnet.PatternType
---@param bnr integer
local function apply_ext_marks(deps, pattern_type, bnr)
  local ns_id = constants.ns_id

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)
  buffer_state[bnr] = {}

  local deduped = vim.iter(deps):filter(function(p) return p.isOutdated end):fold({}, function(acc, p)
    if not acc[p.name] then acc[p.name] = p end
    return acc
  end)

  for _, pkg in pairs(deduped) do
    local line = find_package_in_buffer(pkg.name, pattern_type, bnr)
    if line then
      local extmark_id = vim.api.nvim_buf_set_extmark(bnr, ns_id, line - 1, 0, {
        virt_text = { { string.format("%s -> %s", pkg.currentVersion, pkg.latestVersion), "EasyDotnetPackage" } },
        virt_text_pos = "eol",
        priority = 200,
      })
      buffer_state[bnr][line] = { pkg = pkg, extmark_id = extmark_id, line = line }
    else
      logger.warn("Failed to find package " .. pkg.name)
    end
  end

  set_buffer_keymaps(bnr)
end

M.outdated = function()
  local path = vim.api.nvim_buf_get_name(0)
  local filename = vim.fs.basename(path):lower()
  local bnr = vim.api.nvim_get_current_buf()
  local ns_id = constants.ns_id

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)
  buffer_state[bnr] = {}

  if constants.dotnet_files.is_any_project(path) then
    client:initialize(function()
      client:outdated_packages(path, function(res) apply_ext_marks(res, "reference", bnr) end)
    end)
  elseif filename == constants.dotnet_files.directory_packages_props or filename == constants.dotnet_files.packages_props then
    client:initialize(function()
      client:outdated_packages(current_solution.try_get_selected_solution() or "", function(res) apply_ext_marks(res, "version", bnr) end)
    end)
  elseif filename == constants.dotnet_files.directory_build_props then
    client:initialize(function()
      client:outdated_packages(current_solution.try_get_selected_solution() or "", function(res) apply_ext_marks(res, "reference", bnr) end)
    end)
  else
    logger.error("Current buffer is not *.csproj, *.fsproj, directory.packages.props, packages.props or directory.build.props")
  end
end

return M
