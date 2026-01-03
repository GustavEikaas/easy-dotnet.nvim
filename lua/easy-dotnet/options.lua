---@class easy-dotnet.Options
---@field test_runner easy-dotnet.TestRunner.Options
---@field lsp easy-dotnet.LspOpts
---@field csproj_mappings boolean
---@field fsproj_mappings boolean
---@field new { project: {prefix: "sln" | "none"} }
---@field enable_filetypes boolean
---@field picker easy-dotnet.PickerType
---@field notifications easy-dotnet.Notifications
---@field diagnostics easy-dotnet.DiagnosticsOptions

---@class easy-dotnet.Notifications
---@field handler fun(start_event: easy-dotnet.Job.Event): fun(finished_event: easy-dotnet.Job.Event)

---@class easy-dotnet.LspOpts
---@field enabled boolean                -- Whether the LSP is enabled
---@field analyzer_assemblies string[]|nil -- Optional list of analyzer DLLs
---@field roslynator_enabled boolean     -- Whether Roslynator is enabled
---@field config vim.lsp.config?          -- LSP configuration table

---@class easy-dotnet.DiagnosticsOptions
---@field default_severity "error" | "warning"
---@field setqflist boolean

---@class easy-dotnet.TestRunner.Icons
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

---@class easy-dotnet.TestRunner.Mappings
---@field run_test_from_buffer easy-dotnet.Keymap
---@field peek_stack_trace_from_buffer easy-dotnet.Keymap
---@field debug_test_from_buffer easy-dotnet.Keymap
---@field go_to_file easy-dotnet.Keymap
---@field debug_test easy-dotnet.Keymap
---@field filter_failed_tests easy-dotnet.Keymap
---@field expand_all easy-dotnet.Keymap
---@field collapse_all easy-dotnet.Keymap
---@field expand easy-dotnet.Keymap
---@field peek_stacktrace easy-dotnet.Keymap
---@field run_all easy-dotnet.Keymap
---@field run easy-dotnet.Keymap
---@field close easy-dotnet.Keymap
---@field refresh_testrunner easy-dotnet.Keymap

---@class easy-dotnet.Keymap
---@field lhs string
---@field desc string

---@class easy-dotnet.TestRunner.Options
---@field viewmode string
---@field vsplit_width number|nil
---@field vsplit_pos string|nil
---@field enable_buffer_test_execution boolean
---@field noBuild boolean
---@field icons easy-dotnet.TestRunner.Icons
---@field mappings easy-dotnet.TestRunner.Mappings
---@field additional_args table

---@alias easy-dotnet.PickerType nil | "telescope" | "fzf" | "snacks" | "basic"

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
  ---@type easy-dotnet.Options
  options = {
    ---@param path string
    ---@param action "test"|"restore"|"build"|"run"|"watch"
    ---@param args string
    terminal = function(path, action, args, ctx)
      args = args or ""
      local commands = {
        run = function() return string.format("%s %s", ctx.cmd, args) end,
        test = function() return string.format("%s %s", ctx.cmd, args) end,
        restore = function() return string.format("%s %s", ctx.cmd, args) end,
        build = function() return string.format("%s %s", ctx.cmd, args) end,
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
    ---@type easy-dotnet.TestRunner.Options
    test_runner = {
      viewmode = "float",
      vsplit_width = nil,
      vsplit_pos = nil,
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
        peek_stack_trace_from_buffer = { lhs = "<leader>p", desc = "peek stack trace from buffer" },
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
    server = {
      use_visual_studio = false,
      ---@type nil | "Off" | "Critical" | "Error" | "Warning" | "Information" | "Verbose" | "All"
      log_level = nil,
    },
    enable_filetypes = true,
    auto_bootstrap_namespace = {
      type = "block_scoped",
      enabled = true,
      use_clipboard_json = {
        behavior = "prompt", --'auto' | 'prompt' | 'never',
        register = "+",
      },
    },
    -- choose which picker to use with the plugin
    -- possible values are "telescope" | "fzf" | "snacks" | "basic"
    -- if nil, will auto-detect available pickers in order: telescope -> fzf -> basic
    ---@type easy-dotnet.PickerType
    picker = nil,
    --For performance reasons this will query msbuild properties as soon as vim starts
    background_scanning = true,
    notifications = {
      --Set this to false if you have configured lualine to avoid double logging
      handler = function(start_event)
        local spinner = require("easy-dotnet.ui-modules.spinner").new()
        spinner:start_spinner(function() return start_event.job.name end)
        ---@param finished_event easy-dotnet.Job.Event
        return function(finished_event) spinner:stop_spinner(finished_event.result.msg, finished_event.result.level) end
      end,
    },
    debugger = {
      mappings = {
        open_variable_viewer = { lhs = "T", desc = "open variable viewer" },
      },
      bin_path = nil,
      apply_value_converters = true,
      auto_register_dap = true,
    },
    projx_lsp = {
      enabled = false,
    },
    lsp = {
      enabled = true,
      analyzer_assemblies = {},
      roslynator_enabled = true,
      config = {},
    },
    diagnostics = {
      default_severity = "error",
      setqflist = false,
    },
  },
}

local function merge_tables(default_options, user_options) return vim.tbl_deep_extend("keep", user_options, default_options) end

--- Auto_bootstrap namespace can be either true or table with config
local function handle_auto_bootstrap_namespace(a)
  if type(a.auto_bootstrap_namespace) == "boolean" then a.auto_bootstrap_namespace = {
    type = "block_scoped",
    enabled = a.auto_bootstrap_namespace,
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
