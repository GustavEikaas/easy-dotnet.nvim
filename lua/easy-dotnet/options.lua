---@class easy-dotnet.ManagedTerminal.Mappings
---@field next_tab easy-dotnet.Keymap
---@field prev_tab easy-dotnet.Keymap
---@field new_terminal easy-dotnet.Keymap
---@field close_terminal easy-dotnet.Keymap
---@field hide_panel easy-dotnet.Keymap

---@class easy-dotnet.ManagedTerminal
---@field auto_hide boolean
---@field auto_hide_delay integer
---@field mappings easy-dotnet.ManagedTerminal.Mappings

---@class easy-dotnet.Options
---@field external_terminal easy-dotnet.ExternalTerminal|nil
---@field test_runner easy-dotnet.TestRunner.Options
---@field lsp easy-dotnet.LspOpts
---@field csproj_mappings boolean
---@field fsproj_mappings boolean
---@field new { project: {prefix: "sln" | "none"} }
---@field enable_filetypes boolean
---@field picker easy-dotnet.PickerType
---@field notifications easy-dotnet.Notifications
---@field diagnostics easy-dotnet.DiagnosticsOptions
---@field outdated easy-dotnet.Outdated.Options

---@class easy-dotnet.ExternalTerminal
---@field command string
---@field args string[]

---@class easy-dotnet.Notifications
---@field handler fun(start_event: easy-dotnet.Job.Event): fun(finished_event: easy-dotnet.Job.Event)

---@class easy-dotnet.LspOpts
---@field enabled boolean                -- Whether the LSP is enabled
---@field set_fold_expr boolean
---@field preload_roslyn boolean
---@field analyzer_assemblies string[]|nil -- Optional list of analyzer DLLs
---@field easy_dotnet_analyzer_enabled boolean -- Whether built-in easy-dotnet roslyn analyzer is enabled
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
---@field class string

---@class easy-dotnet.TestRunner.Mappings
---@field run_test_from_buffer easy-dotnet.Keymap
---@field run_all_tests_from_buffer easy-dotnet.Keymap
---@field get_build_errors easy-dotnet.Keymap
---@field peek_stack_trace_from_buffer easy-dotnet.Keymap
---@field debug_test_from_buffer easy-dotnet.Keymap
---@field debug_test easy-dotnet.Keymap
---@field go_to_file easy-dotnet.Keymap
---@field run_all easy-dotnet.Keymap
---@field run easy-dotnet.Keymap
---@field peek_stacktrace easy-dotnet.Keymap
---@field expand easy-dotnet.Keymap
---@field expand_node easy-dotnet.Keymap
---@field collapse_all easy-dotnet.Keymap
---@field refresh_testrunner easy-dotnet.Keymap
---@field close easy-dotnet.Keymap
---@field cancel easy-dotnet.Keymap

---@class easy-dotnet.Keymap
---@field lhs string
---@field desc string

---@class easy-dotnet.TestRunner.Options
---@field viewmode string
---@field vsplit_width number|nil
---@field vsplit_pos string|nil
---@field icons easy-dotnet.TestRunner.Icons
---@field mappings easy-dotnet.TestRunner.Mappings

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
    managed_terminal = {
      auto_hide = true,
      auto_hide_delay = 1000,
      mappings = {
        next_tab = { lhs = "<Tab>", desc = "Next terminal tab" },
        prev_tab = { lhs = "<S-Tab>", desc = "Previous terminal tab" },
        new_terminal = { lhs = "+", desc = "New user terminal" },
        close_terminal = { lhs = "X", desc = "Close current terminal tab" },
        hide_panel = { lhs = "q", desc = "Hide terminal panel" },
      },
    },
    -- Optional configuration for external terminals (matches nvim-dap structure)
    external_terminal = nil,
    secrets = {
      path = get_secret_path,
    },
    ---@type easy-dotnet.TestRunner.Options
    test_runner = {
      auto_start_testrunner = true,
      hide_legend = false,
      viewmode = "float",
      vsplit_width = nil,
      vsplit_pos = nil,
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
        class = "",
        build_failed = "󰒡",
      },
      mappings = {
        run_test_from_buffer = { lhs = "<leader>r", desc = "run test from buffer" },
        run_all_tests_from_buffer = { lhs = "<leader>t", desc = "Run all tests in file" },
        get_build_errors = { lhs = "<leader>e", desc = "get build errors" },
        peek_stack_trace_from_buffer = { lhs = "<leader>p", desc = "peek stack trace from buffer" },
        debug_test_from_buffer = { lhs = "<leader>d", desc = "run test from buffer" },
        debug_test = { lhs = "<leader>d", desc = "debug test" },
        go_to_file = { lhs = "<leader>g", desc = "go to file" },
        run_all = { lhs = "<leader>R", desc = "run all tests" },
        run = { lhs = "<leader>r", desc = "run test" },
        peek_stacktrace = { lhs = "<leader>p", desc = "peek stacktrace of failed test" },
        expand = { lhs = "o", desc = "expand" },
        expand_node = { lhs = "E", desc = "expand node" },
        collapse_all = { lhs = "W", desc = "collapse all" },
        close = { lhs = "q", desc = "close testrunner" },
        refresh_testrunner = { lhs = "<C-r>", desc = "refresh testrunner" },
        cancel = { lhs = "<C-c>", desc = "cancel in-flight operation" },
      },
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
      console = "integratedTerminal", --externalTerminal
      bin_path = nil,
      apply_value_converters = true,
      auto_register_dap = true,
    },
    projx_lsp = {
      enabled = false,
    },
    lsp = {
      enabled = true,
      set_fold_expr = false,
      preload_roslyn = true,
      analyzer_assemblies = {},
      auto_refresh_codelens = true,
      roslynator_enabled = true,
      easy_dotnet_analyzer_enabled = true,
      config = {},
    },
    diagnostics = {
      default_severity = "error",
      setqflist = false,
    },
    outdated = {
      mappings = {
        upgrade = { lhs = "<leader>pu", desc = "upgrade package under cursor" },
        upgrade_all = { lhs = "<leader>pa", desc = "upgrade all outdated packages" },
      },
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
