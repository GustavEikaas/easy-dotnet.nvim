---@class TestRunnerOptions
---@field noBuild boolean
---@field noRestore boolean
---@field viewmode "float" | "buf" | "split"
---@field icons table<string>
---@field additional_args table<string> | nil

local function get_sdk_path()
  local sdk_version = vim.system({ "dotnet", "--version" }):wait().stdout:gsub("\r", ""):gsub("\n", "")
  local isWindows = require("easy-dotnet.extensions").isWindows()
  local base = isWindows and "C:/Program Files/dotnet/sdk" or "/usr/lib/dotnet/sdk"
  local sdk_path = vim.fs.joinpath(base, sdk_version)
  return sdk_path
end

local function get_secret_path(secret_guid)
  local path = ""
  local home_dir = vim.fn.expand('~')
  if require("easy-dotnet.extensions").isWindows() then
    local secret_path = home_dir ..
        '\\AppData\\Roaming\\Microsoft\\UserSecrets\\' .. secret_guid .. "\\secrets.json"
    path = secret_path
  else
    local secret_path = home_dir .. "/.microsoft/usersecrets/" .. secret_guid .. "/secrets.json"
    path = secret_path
  end
  return path
end

return {
  ---@type function | string
  get_sdk_path = get_sdk_path,
  ---@param path string
  ---@param action "test"|"restore"|"build"|"run"
  ---@param args string
  terminal = function(path, action, args)
    local commands = {
      run = function()
        return string.format("dotnet run --project %s %s", path, args)
      end,
      test = function()
        return string.format("dotnet test %s %s", path, args)
      end,
      restore = function()
        return string.format("dotnet restore %s %s", path, args)
      end,
      build = function()
        return string.format("dotnet build %s %s", path, args)
      end
    }
    local command = commands[action]()
    if require("easy-dotnet.extensions").isWindows() == true then
      command = command .. "\r"
    end
    vim.cmd("vsplit")
    vim.cmd("term " .. command)
  end,
  secrets = {
    path = get_secret_path,
  },
  ---@type TestRunnerOptions
  test_runner = {
    viewmode = "split",
    noBuild = true,
    noRestore = true,
      icons = {
        passed = "",
        skipped = "",
        failed = "",
        success = "",
        reload = "",
        test = "",
        sln = "󰘐",
        project = "󰘐",
        dir = "",
        package = "",
      },
    additional_args = {},
  },
  csproj_mappings = true,
  fsproj_mappings = true,
  auto_bootstrap_namespace = true
}
