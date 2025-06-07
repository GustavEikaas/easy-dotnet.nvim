local polyfills = require("easy-dotnet.polyfills")
local constants = require("easy-dotnet.constants")
local logger = require("easy-dotnet.logger")
local M = {}

---@alias PatternType "reference" | "version"

---@class PackageInfo
---@field Name string
---@field ResolvedVersion string
---@field LatestVersion string

local function read_package_info(path, project_name)
  local success, contents = pcall(vim.fn.readfile, path)
  if not success then return {} end
  local parsed_json = vim.fn.json_decode(table.concat(contents))
  for _, value in ipairs(parsed_json.Projects) do
    if value.Name == project_name then return value.TargetFrameworks[1].Dependencies end
  end
  return {}
end

---@param path string
---@return PackageInfo[]
local function read_solution_packages_info(path)
  local deps = {}
  local seen = {}
  local success, contents = pcall(vim.fn.readfile, path)
  if not success then return {} end
  local parsed_json = vim.fn.json_decode(table.concat(contents))
  for _, value in ipairs(parsed_json.Projects) do
    for _, dep in ipairs(value.TargetFrameworks[1].Dependencies) do
      if not seen[dep.Name] then
        table.insert(deps, dep)
        seen[dep.Name] = true
      end
    end
  end
  return deps
end

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

-- No outdated dependencies were detected
---@param cmd string
---@param cb function
local function handle_outdated_command(cmd, cb)
  local on_job_finished = require("easy-dotnet.ui-modules.jobs").register_job({ job = "Checking package references", on_error_text = "Checking package references failed" })
  local stderr = {}
  vim.fn.jobstart(cmd, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      if data then stderr = data end
    end,
    on_exit = function(_, b)
      on_job_finished(b == 0)
      if b == 0 then
        cb()
      else
        logger.warn("stderr: " .. vim.inspect(stderr))
      end
    end,
  })
end

---@param deps PackageInfo[]
---@param pattern_type PatternType
local function apply_ext_marks(deps, pattern_type)
  local ns_id = constants.ns_id
  local bnr = vim.fn.bufnr("%")
  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)
  for _, value in ipairs(deps) do
    local line = find_package_in_buffer(value.Name, pattern_type)
    if line ~= nil then
      vim.api.nvim_buf_set_extmark(bnr, ns_id, line - 1, 0, {
        virt_text = { { string.format("%s -> %s", value.ResolvedVersion, value.LatestVersion), "EasyDotnetPackage" } },
        virt_text_pos = "eol",
        priority = 200,
      })
    else
      logger.warn("Failed to find package " .. value.Name)
    end
  end
end

M.outdated = function()
  local path = vim.fs.normalize(vim.fn.expand("%"))
  local filename = vim.fs.basename(path):lower()
  local bnr = vim.fn.bufnr("%")
  local ns_id = constants.ns_id

  local data_dir = constants.get_data_directory()
  local out_path = polyfills.fs.joinpath(data_dir, "package.json")

  os.remove(out_path) -- Delete the package.json file if it exists

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)

  if path:match("[^/\\]+%.%a+proj") then
    local project_name = vim.fs.basename(path:gsub("%.csproj$", ""):gsub("%.fsproj$", ""))
    local cmd = string.format("dotnet outdated %s --output %s", path, out_path)

    handle_outdated_command(cmd, function()
      local deps = read_package_info(out_path, project_name)

      if #deps == 0 then
        logger.info("All packages are up to date")
        return
      end

      apply_ext_marks(deps, "reference")
    end)
  elseif filename == "directory.packages.props" or filename == "packages.props" then
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local solutionFilePath = sln_parse.find_solution_file()
    local cmd = string.format("dotnet outdated %s --output %s", solutionFilePath, out_path)

    handle_outdated_command(cmd, function()
      local deps = read_solution_packages_info(out_path)

      if #deps == 0 then
        logger.info("All packages are up to date")
        return
      end

      apply_ext_marks(deps, "version")
    end)
  elseif filename == "directory.build.props" then
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local solutionFilePath = sln_parse.find_solution_file()
    local cmd = string.format("dotnet outdated %s --output %s", solutionFilePath, out_path)

    handle_outdated_command(cmd, function()
      local deps = read_solution_packages_info(out_path)

      if #deps == 0 then
        logger.info("All packages are up to date")
        return
      end

      apply_ext_marks(deps, "reference")
    end)
  else
    logger.error("Current buffer is not *.csproj, *.fsproj, directory.packages.props, packages.props or directory.build.props")
  end
end

return M
