local polyfills = require("easy-dotnet.polyfills")
local logger = require("easy-dotnet.logger")

-- Define constants for pattern types
local PATTERN_TYPE_REFERENCE = "reference"
local PATTERN_TYPE_VERSION = "version"

local M = {}

local function readFile(filePath)
  local file = io.open(filePath, "r")
  if not file then return nil end

  local content = {}
  for line in file:lines() do
    table.insert(content, line)
  end

  file:close()
  return content
end

local function readPackageInfo(path, project_name)
  local contents = readFile(path)
  if contents == nil then
    error("Failed to read file " .. vim.fs.basename(path))
    return
  end
  local parsedJson = vim.fn.json_decode(table.concat(contents))
  for _, value in ipairs(parsedJson.Projects) do
    if value.Name == project_name then return value.TargetFrameworks[1].Dependencies end
  end
  return {}
end

local function readSolutionPackagesInfo(path)
  local deps = {}
  local seen = {}
  local contents = readFile(path)
  if contents == nil then
    error("Failed to read file " .. vim.fs.basename(path))
    return
  end
  local parsedJson = vim.fn.json_decode(table.concat(contents))
  for _, value in ipairs(parsedJson.Projects) do
    for _, dep in ipairs(value.TargetFrameworks[1].Dependencies) do
      if not seen[dep.Name] then
        table.insert(deps, dep)
        seen[dep.Name] = true
      end
    end
  end
  return deps
end

local function find_package_in_buffer(package_name, pattern_type)
  local buf = vim.api.nvim_get_current_buf()

  -- Escape dots and hyphens in package name
  local escaped_package_name = package_name:gsub("[%.%-]", "%%%1")

  -- Define the pattern based on the type
  local pattern
  if pattern_type == PATTERN_TYPE_REFERENCE then
    pattern = '<PackageReference Include="' .. escaped_package_name .. '"'
  elseif pattern_type == PATTERN_TYPE_VERSION then
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

M.outdated = function()
  local path = vim.fs.normalize(vim.fn.expand("%"))
  local filename = vim.fs.basename(path):lower()
  local bnr = vim.fn.bufnr("%")
  local ns_id = require("easy-dotnet.constants").ns_id

  local data_dir = require("easy-dotnet.constants").get_data_directory()
  local outPath = polyfills.fs.joinpath(data_dir, "package.json")

  os.remove(outPath) -- Delete the package.json file if it exists

  vim.api.nvim_buf_clear_namespace(bnr, ns_id, 0, -1)

  if path:match("[^/\\]+%.%a+proj") then
    local project_name = vim.fs.basename(path:gsub("%.csproj$", ""):gsub("%.fsproj$", ""))
    local cmd = string.format("dotnet outdated %s --output %s", path, outPath)

    vim.fn.jobstart(cmd, {
      on_exit = function(_, b)
        if b == 0 then
          local file = io.open(outPath, "r")
          if not file then return end
          file:close()

          local deps = readPackageInfo(outPath, project_name)
          if deps == nil then
            error("Parsing outdated packages failed")
            return
          end

          if #deps == 0 then
            logger.info("All packages are up to date")
            return
          end

          for _, value in ipairs(deps) do
            local line = find_package_in_buffer(value.Name, PATTERN_TYPE_REFERENCE)
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
        else
          logger.error("Dotnet outdated tool not installed")
        end
      end,
    })
  elseif filename == "directory.packages.props" or filename == "packages.props" then
    local sln_parse = require("easy-dotnet.parsers.sln-parse")
    local solutionFilePath = sln_parse.find_solution_file()
    local cmd = string.format("dotnet outdated %s --output %s", solutionFilePath, outPath)

    vim.fn.jobstart(cmd, {
      on_exit = function(_, b)
        if b == 0 then
          local file = io.open(outPath, "r")
          if not file then return end
          file:close()

          local deps = readSolutionPackagesInfo(outPath)
          if deps == nil then
            error("Parsing outdated packages failed")
            return
          end

          if #deps == 0 then
            logger.info("All packages are up to date")
            return
          end

          for _, value in ipairs(deps) do
            local line = find_package_in_buffer(value.Name, PATTERN_TYPE_VERSION)
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
        else
          logger.info("Dotnet outdated tool not installed")
        end
      end,
    })
  else
    logger.error("Current buffer is not *.csproj, *.fsproj, directory.packages.props or packages.props")
  end
end
return M
