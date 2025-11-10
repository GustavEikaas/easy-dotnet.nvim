local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local constants = require("easy-dotnet.constants")
local logger = require("easy-dotnet.logger")
local M = {}

---@alias PatternType "reference" | "version"

---@param package_name string # The name of the package to search for.
---@param pattern_type PatternType # The pattern type to use ("reference" or "version").
---@return integer|nil # Returns the line number where the package is found, or nil if not found
local function find_package_in_buffer(package_name, pattern_type)
  local buf = vim.api.nvim_get_current_buf()

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

  local num_lines = vim.api.nvim_buf_line_count(buf)

  for line_number = 1, num_lines do
    local line = vim.api.nvim_buf_get_lines(buf, line_number - 1, line_number, false)[1]
    if line and line:match(pattern) then return line_number end
  end

  return nil
end

---@param deps OutdatedPackage[]
---@param pattern_type PatternType
local function apply_ext_marks(deps, pattern_type)
  local ns_id = constants.ns_id
  local bnr = vim.fn.bufnr("%")

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)

  local deduped = vim.iter(deps):filter(function(p) return p.isOutdated end):fold({}, function(acc, p)
    if not acc[p.name] then acc[p.name] = p end
    return acc
  end)

  for _, pkg in pairs(deduped) do
    local line = find_package_in_buffer(pkg.name, pattern_type)
    if line then
      vim.api.nvim_buf_set_extmark(bnr, ns_id, line - 1, 0, {
        virt_text = { { string.format("%s -> %s", pkg.currentVersion, pkg.latestVersion), "EasyDotnetPackage" } },
        virt_text_pos = "eol",
        priority = 200,
      })
    else
      logger.warn("Failed to find package " .. pkg.name)
    end
  end
end

M.outdated = function()
  local path = vim.api.nvim_buf_get_name(0)
  local filename = vim.fs.basename(path):lower()
  local bnr = vim.fn.bufnr("%")
  local ns_id = constants.ns_id

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)

  if constants.dotnet_files.is_any_project(path) then
    client:initialize(function()
      client:outdated_packages(path, function(res) apply_ext_marks(res, "reference") end)
    end)
  elseif filename == constants.dotnet_files.directory_packages_props or filename == constants.dotnet_files.packages_props then
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local solution_file_path = sln_parse.find_solution_file()
    client:initialize(function()
      client:outdated_packages(solution_file_path or "", function(res) apply_ext_marks(res, "version") end)
    end)
  elseif filename == constants.dotnet_files.directory_build_props then
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local solution_file_path = sln_parse.find_solution_file()
    client:initialize(function()
      client:outdated_packages(solution_file_path or "", function(res) apply_ext_marks(res, "reference") end)
    end)
  else
    logger.error("Current buffer is not *.csproj, *.fsproj, directory.packages.props, packages.props or directory.build.props")
  end
end

return M
