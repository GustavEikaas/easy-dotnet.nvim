---@class TestRunnerIcons
---@field passed string
---@field skipped string
---@field failed string
---@field success string
---@field reload string
---@field test string
---@field sln string
---@field project string
---@field dir string
---@field package string

---@class TestRunnerMappings
---@field run_test_from_buffer Keymap
---@field debug_test_from_buffer Keymap
---@field go_to_file Keymap
---@field debug_test Keymap
---@field filter_failed_tests Keymap
---@field expand_all Keymap
---@field collapse_all Keymap
---@field expand Keymap
---@field peek_stacktrace Keymap
---@field run_all Keymap
---@field run Keymap
---@field close Keymap
---@field refresh_testrunner Keymap

---@class Keymap
---@field lhs string
---@field desc string

---@class TestRunnerOptions
---@field viewmode string
---@field enable_buffer_test_execution boolean
---@field noBuild boolean
---@field noRestore boolean
---@field icons TestRunnerIcons
---@field mappings TestRunnerMappings
---@field additional_args table

local function get_sdk_path()
  local sdk_version = vim.trim(vim.system({ "dotnet", "--version" }):wait().stdout)
  local sdk_list = vim.trim(vim.system({ "dotnet", "--list-sdks" }):wait().stdout)
  local base = nil
  for line in sdk_list:gmatch("[^\n]+") do
    if line:find(sdk_version, 1, true) then
      base = vim.fs.normalize(line:match("%[(.-)%]"))
      break
    end
  end
  local sdk_path = vim.fs.joinpath(base, sdk_version):gsub("Program Files", '"Program Files"')
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


local M = {
  options = {
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
      enable_buffer_test_execution = true,
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
      mappings = {
        run_test_from_buffer = { lhs = "<leader>r", desc = "run test from buffer" },
        debug_test_from_buffer = { lhs = "<leader>d", desc = "run test from buffer" },
        filter_failed_tests = { lhs = "<leader>fe", desc = "filter failed tests" },
        debug_test = { lhs = "<leader>d", desc = "debug test" },
        go_to_file = { lhs = "g", desc = "got to file" },
        run_all = { lhs = "<leader>R", desc = "run all tests" },
        run = { lhs = "<leader>r", desc = "run test" },
        peek_stacktrace = { lhs = "<leader>p", desc = "peek stacktrace of failed test" },
        expand = { lhs = "o", desc = "expand" },
        expand_node = { lhs = "E", desc = "expand node" },
        expand_all = { lhs = "-", desc = "expand all" },
        collapse_all = { lhs = "W", desc = "collapse all" },
        close = { lhs = "q", desc = "close testrunner" },
        refresh_testrunner = { lhs = "<C-r>", desc = "refresh testrunner" }
      },
      additional_args = {},
    },
    csproj_mappings = true,
    fsproj_mappings = true,
    auto_bootstrap_namespace = true,
    enable_filetypes = true,
  }
}

local function merge_tables(default_options, user_options)
  return vim.tbl_deep_extend("keep", user_options, default_options)
end

M.set_options = function(a)
  M.options = merge_tables(M.options, a)
  return M.options
end

return M
