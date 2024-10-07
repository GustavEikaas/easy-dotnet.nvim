local M = {}

local function readFile(filePath)
  local file = io.open(filePath, "r")
  if not file then
    return nil
  end

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
    error("failed to read file")
    return
  end
  local parsedJson = vim.fn.json_decode(table.concat(contents))
  for _, value in ipairs(parsedJson.Projects) do
    if value.Name == project_name then
      return value.TargetFrameworks[1].Dependencies
    end
  end
  return {}
end

local function find_package_reference_in_buffer(package_name)
  local buf = vim.api.nvim_get_current_buf()

  local pattern = '<PackageReference Include="' .. package_name:gsub("%.", "%%.") .. '"'

  local num_lines = vim.api.nvim_buf_line_count(buf)

  for line_number = 1, num_lines do
    local line = vim.api.nvim_buf_get_lines(buf, line_number - 1, line_number, false)[1]
    if line and line:match(pattern) then
      return line_number
    end
  end

  return nil
end

M.outdated = function()
  local path = vim.fn.expand("%")
  if path:match(".csproj$") then
    --TODO: constants.get_data_dir
    local project_name = path:match("([^/]+)%.csproj$")
    local outPath = vim.fn.stdpath("data") .. "/easy-dotnet/package.json"
    local cmd = string.format("dotnet-outdated %s --output %s", path, outPath)
    vim.fn.jobstart(cmd, {
      on_exit = function(_, b)
        if b == 0 then
          local deps = readPackageInfo(outPath, project_name)
          if deps == nil then
            error("Parsing outdated packages failed")
            return
          end

          if #deps == 0 then
            vim.notify("All packages are up to date", vim.log.levels.INFO)
            return
          end

          local bnr = vim.fn.bufnr('%')
          local ns_id = require("easy-dotnet.constants").ns_id
          for _, value in ipairs(deps) do
            local line = find_package_reference_in_buffer(value.Name)
            if line ~= nil then
              vim.api.nvim_buf_set_extmark(bnr, ns_id, line - 1, 0, {
                virt_text = { { string.format("%s -> %s", value.ResolvedVersion, value.LatestVersion), "EasyDotnetPackage" } },
                virt_text_pos = "eol",
                priority = 200,
              })
            else
              vim.notify("Failed to find package " .. value.Name, vim.log.levels.DEBUG)
            end
          end
        else
          vim.notify("Dotnet outdated tool not installed")
        end
      end,
    })
  else
    vim.notify("Current buffer is not a .csproj file")
  end
end
return M
