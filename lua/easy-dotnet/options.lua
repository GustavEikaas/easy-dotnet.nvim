local polyfills = require("easy-dotnet.polyfills")
---@class Options
---@field get_sdk_path fun(): string
---@field test_runner TestRunnerOptions
---@field csproj_mappings boolean
---@field fsproj_mappings boolean
---@field new { project: {prefix: "sln" | "none"} }
---@field enable_filetypes boolean
---@field picker PickerType
---@field notifications Notifications

---@class Notifications
---@field handler fun(start_event: JobEvent): fun(finished_event: JobEvent)

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
---@field vsplit_width number|nil
---@field enable_buffer_test_execution boolean
---@field noBuild boolean
---@field icons TestRunnerIcons
---@field mappings TestRunnerMappings
---@field additional_args table

---@alias PickerType nil | "telescope" | "fzf" | "snacks" | "basic"

local function get_sdk_path()
  local sdk_version = vim.trim(vim.fn.system("dotnet --version"))
  local sdk_list = vim.trim(vim.fn.system("dotnet --list-sdks"))
  local base = nil
  for line in sdk_list:gmatch("[^\n]+") do
    if line:find(sdk_version, 1, true) then
      local path = line:match("%[(.-)%]")
      if not path then error("no sdk path found calling dotnet --list-sdks " .. (path or "empty")) end
      base = vim.fs.normalize(path)
      break
    end
  end
  local sdk_path = polyfills.fs.joinpath(base, sdk_version)
  return sdk_path
end

local function get_secret_path(secret_guid)
  local path
  local home_dir = vim.fn.expand("~")
  if require("easy-dotnet.extensions").isWindows() then
    local secret_path = home_dir .. "\\AppData\\Roaming\\Microsoft\\UserSecrets\\" .. secret_guid .. "\\secrets.json"
    path = secret_path
  else
    local secret_path = home_dir .. "/.microsoft/usersecrets/" .. secret_guid .. "/secrets.json"
    path = secret_path
  end
  return path
end

local M = {
  ---@type Options
  options = {
    ---@type function | string
    get_sdk_path = get_sdk_path,
    ---@param path string
    ---@param action "test"|"restore"|"build"|"run"|"watch"
    ---@param args string
    terminal = function(path, action, args)
      args = args or ""
      local commands = {
        run = function() return string.format("dotnet run --project %s %s", path, args) end,
        test = function() return string.format("dotnet test %s %s", path, args) end,
        restore = function() return string.format("dotnet restore %s %s", path, args) end,
        build = function() return string.format("dotnet build %s %s", path, args) end,
        watch = function() return string.format("dotnet watch --project %s %s", path, args) end,
      }
      local command = commands[action]()
      if require("easy-dotnet.extensions").isWindows() == true then command = command .. "\r" end
      vim.cmd("vsplit")
      vim.cmd("term " .. command)
    end,
    secrets = {
      path = get_secret_path,
    },
    ---@type TestRunnerOptions
    test_runner = {
      viewmode = "split",
      vsplit_width = nil,
      enable_buffer_test_execution = true,
      noBuild = true,
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
        go_to_file = { lhs = "g", desc = "go to file" },
        run_all = { lhs = "<leader>R", desc = "run all tests" },
        run = { lhs = "<leader>r", desc = "run test" },
        peek_stacktrace = { lhs = "<leader>p", desc = "peek stacktrace of failed test" },
        expand = { lhs = "o", desc = "expand" },
        expand_node = { lhs = "E", desc = "expand node" },
        expand_all = { lhs = "-", desc = "expand all" },
        collapse_all = { lhs = "W", desc = "collapse all" },
        close = { lhs = "q", desc = "close testrunner" },
        refresh_testrunner = { lhs = "<C-r>", desc = "refresh testrunner" },
      },
      additional_args = {},
    },
    csproj_mappings = true,
    fsproj_mappings = true,
    new = {
      project = {
        prefix = "sln",
      },
    },
    enable_filetypes = true,
    auto_bootstrap_namespace = {
      type = "block_scoped",
      enabled = true,
    },
    -- choose which picker to use with the plugin
    -- possible values are "telescope" | "fzf" | "snacks" | "basic"
    -- if nil, will auto-detect available pickers in order: telescope -> fzf -> basic
    ---@type PickerType
    picker = nil,
    --For performance reasons this will query msbuild properties as soon as vim starts
    background_scanning = true,
    notifications = {
      --Set this to false if you have configured lualine to avoid double logging
      handler = function(start_event)
        local spinner = require("easy-dotnet.ui-modules.spinner").new()
        spinner:start_spinner(start_event.job.name)
        ---@param finished_event JobEvent
        return function(finished_event) spinner:stop_spinner(finished_event.result.msg, finished_event.result.level) end
      end,
    },
  },
}

local function merge_tables(default_options, user_options) return vim.tbl_deep_extend("keep", user_options, default_options) end

--- Auto_bootstrap namespace can be either true or table with config
local function handle_auto_bootstrap_namespace(a)
  if type(a.auto_bootstrap_namespace) ~= "table" then a.auto_bootstrap_namespace = {
    type = "block_scoped",
    enabled = a.auto_bootstrap_namespace == true,
  } end
end

M.orig_config = nil

M.set_options = function(a)
  M.orig_config = a
  a = a or {}
  handle_auto_bootstrap_namespace(a)
  M.options = merge_tables(M.options, a)
  return M.options
end

function M.get_option(key) return M.options[key] end

return M
