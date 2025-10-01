[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&size=32&pause=1000&width=435&lines=easy-dotnet.nvim)](https://git.io/typing-svg)
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

> 💡 **Tip:** 
> This plugin and all its features should work for both **C#** and **F#**.

>[!IMPORTANT]
>This plugin now uses [easy-dotnet-server](https://github.com/GustavEikaas/easy-dotnet-server) to enable more advanced functionality. As a result, the server may require more frequent updates.
>Run `:Dotnet _server update` or `dotnet tool install -g EasyDotnet` to update it.
>The plugin will attempt to detect when the server is outdated and notify you. If you encounter any issues, please don't hesitate to file an issue.


>[!IMPORTANT]
>I need feedback! The last months I have had a blast developing this plugin, i have gotten a lot of feedback from you guys, and I want more! Please dont hesitate to file an issue with an improvement/bug/question etc..
>And most importantly thank you guys for using my plugin :D


## Motivation
As a developer transitioning from Rider to Neovim, I found myself missing the simplicity of running projects with just a single button click. Tired of typing out lengthy terminal commands for common tasks like running, testing, and managing user secrets, I decided to create easy-dotnet.nvim. This plugin aims to bridge the gap between the convenience of IDEs like Rider and the flexibility of Neovim.

# Table of Contents

1. [Easy-dotnet.nvim](#easy-dotnet.nvim)
2. [Simplifying .NET development in Neovim](#simplifying-.net-development-in-neovim)
3. [Motivation](#motivation)
4. [Features](#features)
5. [Requirements](#requirements)
6. [Setup](#setup)
   - [Without options](#without-options)
   - [With options](#with-options)
   - [Lualine config](#lualine-config)
7. [Commands](#commands)
   - [Lua functions](#lua-functions)
   - [Vim commands](#vim-commands)
8. [Testrunner](#testrunner)
   - [Keymaps](#keymaps)
   - [Debugging tests](#debugging-tests)
   - [Running tests from buffer](#running-tests-directly-from-buffer)
   - [Debugging tests from buffer](#debugging-tests-directly-from-buffer)
9. [Project view](#project-view)
   - [Features](#features-1)
   - [Keymaps](#keymaps-1)
10. [Workspace Diagnostics](#workspace-diagnostics)
    - [Commands](#commands-1)
    - [Configuration](#configuration)
    - [Features](#features-2)
11. [Outdated](#outdated)
12. [Add](#add)
    - [Add package](#add-package)
13. [.NET Framework](#.net-framework)
    - [Requirements](#requirements-1)
14. [Project mappings](#project-mappings)
    - [Add reference](#add-reference)
    - [Package autocomplete](#package-autocomplete)
15. [New](#new)
    - [Project](#project)
    - [Configuration file](#configuration-file)
    - [Integrating with nvim-tree](#integrating-with-nvim-tree)
    - [Integrating with neo-tree](#integrating-with-neo-tree)
    - [Integrating with mini.files](#integrating-with-mini-files)
    - [Integrating with snacks.explorer](#integrating-with-snacks-explorer)
16. [EntityFramework](#entityframework)
    - [Database](#database)
    - [Migrations](#migrations)
17. [Language injections](#language-injections)
    - [Showcase](#showcase)
    - [Requirements](#requirements-2)
    - [Support matrix](#support-matrix)
18. [Nvim-dap configuration](#nvim-dap-configuration)
19. [Troubleshooting](#troubleshooting)

## Features

- Solution, slnx, csproj and fsproj support: Whether its a single project or a solution containing multiple projects easy-dotnet has you covered.
- Action Commands: Execute common tasks like building, running, testing, cleaning and restoring with ease.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Debugging Helpers: While easy-dotnet.nvim doesn't set up DAP (Debugger Adapter Protocol) for you, it provides useful helper functions for debugging. These include resolving the DLL you are debugging and rebuilding before launching DAP, ensuring a smooth debugging experience.
- Test runner: Test runner similiar to the one you find in Rider.
- Workspace diagnostics: Get diagnostic errors and warnings from your entire solution or individual projects
- Outdated command: Makes checking outdated packages a breeze using virtual text
- (csproj/fsproj) mappings: Keymappings for .csproj and .fsproj files are automatically available
- Auto bootstrap namespace: Automatically inserts namespace and class/interface when opening a newly created `.cs` file. (also checks clipboard for json to create class from)
- Debugger works out of the box with nvim-dap (if configured)
- Create dotnet templates like with `dotnet new`, automatically adding them to the current solution
- Package autocomplete inside .csproj and .fsproj files [Check it out](#package-autocomplete)
- [Rider-like](https://www.jetbrains.com/help/rider/Language_Injections.html#use-comments)
syntax highlighting for injected languages (sql, json and xml) based on comments

## Requirements

- Neovim needs to be built with **LuaJIT**
- [EasyDotnet](https://www.nuget.org/packages/EasyDotnet) `dotnet tool install -g EasyDotnet`
- `jq`

Although not *required* by the plugin, it is highly recommended to install one of:
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [snacks.nvim](https://github.com/folke/snacks.nvim)

## Setup


>[!IMPORTANT]
>Remember to also setup the cmp source for autocomplete

### Without options
```lua
-- lazy.nvim
{
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = { "nvim-lua/plenary.nvim", 'nvim-telescope/telescope.nvim', },
  config = function()
    require("easy-dotnet").setup()
  end
}
```

### With options
```lua
-- lazy.nvim
{
  "GustavEikaas/easy-dotnet.nvim",
  -- 'nvim-telescope/telescope.nvim' or 'ibhagwan/fzf-lua' or 'folke/snacks.nvim'
  -- are highly recommended for a better experience
  dependencies = { "nvim-lua/plenary.nvim", 'nvim-telescope/telescope.nvim', },
  config = function()
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

    local dotnet = require("easy-dotnet")
    -- Options are not required
    dotnet.setup({
      lsp = {
        enabled = true, -- Enable builtin roslyn lsp
        roslynator_enabled = true, -- Automatically enable roslynator analyzer
        analyzer_assemblies = {}, -- Any additional roslyn analyzers you might use like SonarAnalyzer.CSharp
      },
      debugger = {
        -- The path to netcoredbg executable
        bin_path = nil,
        auto_register_dap = true,
        mappings = {
          open_variable_viewer = { lhs = "T", desc = "open variable viewer" },
        },
      },
      ---@type TestRunnerOptions
      test_runner = {
        ---@type "split" | "vsplit" | "float" | "buf"
        viewmode = "float",
        ---@type number|nil
        vsplit_width = nil,
        ---@type string|nil "topleft" | "topright" 
        vsplit_pos = nil,
        enable_buffer_test_execution = true, --Experimental, run tests directly from buffer
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
          refresh_testrunner = { lhs = "<C-r>", desc = "refresh testrunner" }
        },
        --- Optional table of extra args e.g "--blame crash"
        additional_args = {}
      },
      new = {
        project = {
          prefix = "sln" -- "sln" | "none"
        }
      },
      ---@param action "test" | "restore" | "build" | "run"
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
        path = get_secret_path
      },
      csproj_mappings = true,
      fsproj_mappings = true,
      auto_bootstrap_namespace = {
          --block_scoped, file_scoped
          type = "block_scoped",
          enabled = true,
          use_clipboard_json = {
            behavior = "prompt", --'auto' | 'prompt' | 'never',
            register = "+", -- which register to check
          },
      },
      server = {
          ---@type nil | "Off" | "Critical" | "Error" | "Warning" | "Information" | "Verbose" | "All"
          log_level = nil,
      },
      -- choose which picker to use with the plugin
      -- possible values are "telescope" | "fzf" | "snacks" | "basic"
      -- if no picker is specified, the plugin will determine
      -- the available one automatically with this priority:
      -- telescope -> fzf -> snacks ->  basic
      picker = "telescope",
      background_scanning = true,
      notifications = {
        --Set this to false if you have configured lualine to avoid double logging
        handler = function(start_event)
          local spinner = require("easy-dotnet.ui-modules.spinner").new()
          spinner:start_spinner(start_event.job.name)
          ---@param finished_event JobEvent
          return function(finished_event)
            spinner:stop_spinner(finished_event.result.text, finished_event.result.level)
          end
        end,
      },
      diagnostics = {
        default_severity = "error",
        setqflist = false,
      },
    })

    -- Example command
    vim.api.nvim_create_user_command('Secrets', function()
      dotnet.secrets()
    end, {})

    -- Example keybinding
    vim.keymap.set("n", "<C-p>", function()
      dotnet.run_project()
    end)
  end
}
```

### Lualine config
```lua
local job_indicator = { require("easy-dotnet.ui-modules.jobs").lualine }

require("lualine").setup {
  sections = {
    -- ...
    lualine_a = { "mode", job_indicator },
    -- ...
  },
}
```

## Commands

### Lua functions

**Legend**
- `<TS>` -> Telescope selector
- `<DArgs>` -> Dotnet args (e.g `--no-build`, `--configuration release`). Always optional
- `<TS Default>` -> Telescope selector but persists the selection for all future use 
- `<sln>` -> Solution file (in some cases .csproj or .fsproj is used as fallback if no .sln file exists)

| **Function**                                   | **Description**                                                                                              |
|-----------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| `dotnet.run_profile()`                        | `dotnet run --project <TS> --launch-profile <TS>`                                                                                                       |
| `dotnet.run()` | `dotnet run --project <TS> <DArgs>`                                                                                                             |
| `dotnet.run_default()` | `dotnet run --project <TS Default> <DArgs>` |
| `dotnet.run_profile_default()` | `dotnet run --project <TS Default> --launch-profile <TS> <DArgs>` |
||  
| `dotnet.build()` | `dotnet build <TS> <DArgs>` |
| `dotnet.build_solution()` | `dotnet build <sln> <DArgs>` |
| `dotnet.build_solution_quickfix()` | `dotnet build <sln> <DArgs>` and opens build errors in the quickfix list |
| `dotnet.build_quickfix()` | `dotnet build <TS> <DArgs>` and opens build errors in the quickfix list |
| `dotnet.build_default()` | `dotnet build <TS Default> <DArgs>` |
| `dotnet.build_default_quickfix()` | `dotnet build <TS Default> <DArgs>` and opens build errors in the quickfix list |
||
| `dotnet.project_view()` | Opens the project view |
| `dotnet.project_view_default()` | Opens the project view for your default project |
||
| `dotnet.pack()` | `dotnet pack -c release` |
| `dotnet.push()` | `dotnet pack and push` |
||
| `dotnet.test()` | `dotnet test <TS> <DArgs>` |
| `dotnet.test_solution()` | `dotnet test <TS> <DArgs>` |
| `dotnet.test_default()` | `dotnet test <TS Default> <DArgs>` |
||
| `dotnet.watch()` | `dotnet watch --project <TS> <DArgs>`                                                                                                             |
| `dotnet.watch_default()` | `dotnet watch --project <TS Default> <DArgs>` |
||
| `dotnet.restore()` | `dotnet restore <sln> <Dargs>` |
| `dotnet.clean()`                              | `dotnet clean <sln> <DArgs>`                                                                          |
||
| `dotnet.remove_package()`                              | |
| `dotnet.add_package()`                              | |
||
| `dotnet.testrunner()`                         | Shows or hides the testrunner                                                                                            |
| `dotnet.testrunner_refresh()`                 | Refreshes the testrunner                                                                                                          |
| `dotnet.testrunner_refresh_build()`           | Builds the sln, then refreshes the testrunner                                                                                   |
||
| `dotnet.is_dotnet_project()`                  | Returns `true` if a `.csproj` or `.sln` file is present in the current working directory or subfolders       |
| `dotnet.try_get_selected_solution()`          | If a solution is selected, returns `{ basename: string, path: string }`, otherwise `nil`                    |
| `dotnet.new()`                                | Picker for creating a new template based on `Dotnet new`                                                                                                            |
| `dotnet.outdated()`                           | Runs `Dotnet outdated` in supported file types (`.csproj`, `.fsproj`, `Directory.Packages.props`, `Packages.props`, `Directory.Build.props`) and displays virtual text with the latest package versions. |
||
| `dotnet.solution_select()`                    | Select the solution file for easy-dotnet.nvim to use, useful when multiple .sln files are present in the project.     |
| `dotnet.solution_add()`                       | `dotnet sln <sln> add <TS>`.                                                                                                            |
| `dotnet.solution_remove()`                    | `dotnet sln <sln> remove <TS>`.                                                                                                            |
||
| `dotnet.ef_migrations_remove()`               |  Removes the last applied Entity Framework migration                                                                                                          |
| `dotnet.ef_migrations_add(name: string)`      |  Adds a new Entity Framework migration with the specified name.                                                                                                            |
| `dotnet.ef_migrations_list()`                 |  Lists all applied Entity Framework migrations.                                                                                                           |
| `dotnet.ef_database_drop()`                   |  Drops the database for the selected project.                                                                                                           |
| `dotnet.ef_database_update()`                 |  Updates the database to the latest migration.                                                                                                          |
| `dotnet.ef_database_update_pick()`            |  Opens a picker to update the database to a selected migration.                                                                                                          |
||
| `dotnet.createfile(path)`                     | Spawns a picker for creating a new file based on a `.NET new` template                            |
| `dotnet.secrets()`                            | Opens a picker for `.NET user-secrets`                                                              |
| `dotnet.get_debug_dll()`                      | Returns the DLL from the `bin/debug` folder                                                                 |
| `dotnet.get_environment_variables(project_name, project_path, use_default_launch_profile: boolean)` | Returns the environment variables from the `launchSetting.json` file                                         |
| `dotnet.reset()`                              | Deletes all files persisted by `easy-dotnet.nvim`. Use this if unable to pick a different solution or project |
||
| `diagnostics.get_workspace_diagnostics()`     | Get workspace diagnostics using configured default severity                                                 |
| `diagnostics.get_workspace_diagnostics("error")` | Get workspace diagnostics for errors only                                                                |
| `diagnostics.get_workspace_diagnostics("warning")` | Get workspace diagnostics for errors and warnings                                                       |

```lua
local dotnet = require("easy-dotnet")
dotnet.get_environment_variables(project_name, project_path, use_default_launch_profile: boolean)
dotnet.is_dotnet_project()                                 
dotnet.try_get_selected_solution()                         
dotnet.get_debug_dll()                                     
dotnet.reset()                                             
dotnet.test()
dotnet.test_solution()
dotnet.test_default()
dotnet.testrunner()
dotnet.testrunner_refresh()
dotnet.testrunner_refresh_build()
dotnet.new()
dotnet.outdated()
dotnet.add_package()
dotnet.remove_package()
dotnet.solution_select()
dotnet.ef_migrations_remove()
dotnet.ef_migrations_add(name: string)
dotnet.ef_migrations_list()
dotnet.ef_database_drop()
dotnet.ef_database_update()
dotnet.ef_database_update_pick()
dotnet.createfile(path: string)                                    
dotnet.build()                           
dotnet.build_solution()
dotnet.build_solution_quickfix()
dotnet.build_quickfix()                 
dotnet.build_default()                 
dotnet.build_default_quickfix()       
dotnet.project_view()
dotnet.project_view_default()
dotnet.pack()                           
dotnet.push()                           
dotnet.run()
dotnet.run_profile_default()
dotnet.run_default()
dotnet.watch()
dotnet.watch_default()
dotnet.secrets()                                                          
dotnet.clean()                                                           
dotnet.restore()

local diagnostics = require("easy-dotnet.actions.diagnostics")
diagnostics.get_workspace_diagnostics()
diagnostics.get_workspace_diagnostics("error") 
diagnostics.get_workspace_diagnostics("warning")
```

### Vim commands
```
Run :Dotnet in nvim to list all commands
```
```
Dotnet testrunner
Dotnet testrunner refresh
Dotnet testrunner refresh build
Dotnet run
Dotnet run default
Dotnet run profile
Dotnet run profile default
Dotnet watch
Dotnet watch default
Dotnet test
Dotnet test default
Dotnet test solution
Dotnet build
Dotnet build quickfix
Dotnet build solution
Dotnet build solution quickfix
Dotnet build default
Dotnet build default quickfix
Dotnet add package
Dotnet remove package
Dotnet project view
Dotnet project view default
Dotnet pack
Dotnet push
Dotnet ef database update
Dotnet ef database update pick
Dotnet ef database drop
Dotnet ef migrations add
Dotnet ef migrations remove
Dotnet ef migrations list
Dotnet secrets
Dotnet restore
Dotnet clean
Dotnet new
Dotnet createfile
Dotnet solution select
Dotnet solution add
Dotnet solution remove
Dotnet outdated
Dotnet diagnostic
Dotnet diagnostic errors
Dotnet diagnostic warnings
checkhealth easy-dotnet

-- Internal 
Dotnet reset -- Deletes all persisted files
Dotnet _cached_files -- Preview picker for persisted files
Dotnet _server restart
Dotnet _server update
Dotnet _server stop
Dotnet _server start
```

## Testrunner

Integrated test runner inspired by Rider IDE
![image](https://github.com/user-attachments/assets/874a1ef1-18cb-43f6-a477-834a783cf785)
![image](https://github.com/user-attachments/assets/2d0512f3-f807-4fbd-bf64-a57eb3c06b18)

Should support all test adapters like NUnit, XUnit, MSTest, Expecto etc..
If you are experiencing issues with any test adapter please let me know

- [x] Test runner window
  - [x] Different viewmodes (float/buf/split)
  - [x] Grouped by namespace
  - [x] Passed, skipped, failed
  - [x] Configurable highlights
  - [x] Filter failed tests
  - [x] Test counting
  - [x] Unit test name
  - [x] Collapsable hieararchy 
  - [x] Peek stack trace
  - [x] Run sln,project,namespace,test
  - [x] Aggregate test results
  - [x] Go to file

### Keymaps
- `W` -> Collapse all
- `E` -> Expand all
- `o` -> Expand/collapse under cursor
- `<leader>r` -> Run test under cursor
- `<leader>d` -> `[Experimental]` Debug test under cursor using nvim-dap
- `<leader>R` -> Run all tests
- `<leader>p` -> Peek stacktrace on failed test
- `<leader>fe` -> Show only failed tests

- `g` -> Go to file
- `q` -> Close window
- `<leader>gf` -> Go to file (inside stacktrace float)

### Debugging tests
Using the keybinding `<leader>d` will set a breakpoint in the test and launch nvim-dap

https://github.com/user-attachments/assets/b56891c9-1b65-4522-8057-43eff3d1102d

### Running tests directly from buffer

Gutter signs will appear indicating runnable tests
- `<leader>r` to run test

>[!IMPORTANT]
>Testrunner discovery must have completed before entering the buffer for the signs to appear

![image](https://github.com/user-attachments/assets/1a22fe4d-81c2-4f5a-86b1-c87f7b6fb701)

### Debugging tests directly from buffer

Gutter signs will appear indicating runnable tests
- `<leader>d` to debug test

>[!IMPORTANT]
>Nvim dap must be installed and coreclr adapter must be configured

![image](https://github.com/user-attachments/assets/209aca03-397a-424f-973c-c53bae260031)

## Project view

Get a comprehensive overview of a project's dependencies, and easily manage NuGet packages and project references.

![image](https://github.com/user-attachments/assets/2e0e2e25-0a2b-4864-bc3b-64b4048967e5)

### Features
- **Project Details**: View project name, solution, language, and target version.
- **Project References**:
  - View project references.
  - Add or remove project references.
- **NuGet Packages**:
  - View package references.
  - Add or remove NuGet package references.

### Keymaps

Keymaps are region-specific and work based on context (e.g., when hovering over a project/package or its header):

#### Project References:
- `a`: Add project reference.
- `r`: Remove project reference.

#### Package References:
- `a`: Add package reference.
- `r`: Remove package reference.
- `<C-b>`: View package in browser.

## Workspace Diagnostics

Analyze your entire solution or individual projects for compilation errors and warnings using Roslyn diagnostics.

### Commands

- `Dotnet diagnostic` - Uses the configured default severity (errors by default)
- `Dotnet diagnostic errors` - Shows only compilation errors  
- `Dotnet diagnostic warnings` - Shows both errors and warnings

### Configuration

```lua
require("easy-dotnet").setup({
  diagnostics = {
    default_severity = "error",  -- "error" or "warning" (default: "error")
    setqflist = false,           -- Populate quickfix list automatically (default: false)
  },
})
```

### Features

- **Solution/Project Selection**: When multiple projects or solutions are available, you'll be prompted to select which one to analyze
- **Roslyn Integration**: Uses the Roslyn Language Server Protocol for accurate diagnostics
- **Neovim Diagnostics Integration**: Results are populated into Neovim's built-in diagnostic system, allowing you to:
  - Navigate between diagnostics using `:lua vim.diagnostic.goto_next()` and `:lua vim.diagnostic.goto_prev()`
  - View diagnostics in the quickfix list using `:lua vim.diagnostic.setqflist()` (or automatically if configured)
  - See inline diagnostic messages
  - View with trouble (requires [trouble.nvim](https://github.com/folke/trouble.nvim))
  - View with snacks diagnostic picker (requires [snacks.nvim](https://github.com/folke/snacks.nvim))

The diagnostics will appear in Neovim's diagnostic system, allowing you to navigate through them using your standard diagnostic keymaps. If you have trouble.nvim or snacks.nvim configured, the diagnostics will automatically be available in their respective interfaces.

## Outdated

Run the command `Dotnet outdated` in one of the supported filetypes, virtual text with packages latest version will appear

Supports the following filetypes

- *.csproj
- *.fsproj
- Directory.Packages.props
- Packages.props
- Directory.Build.props


![image](https://github.com/user-attachments/assets/496caec1-a18b-487a-8a37-07c4bb9fa113)

## Add

### Add package

Adding nuget packages are available using the `:Dotnet add package` command. This will allow you to browse for nuget packages.

![image](https://github.com/user-attachments/assets/00a9d38a-6afe-42ec-b971-04191fee1d59)

### Requirements

This functionality relies on `jq` so ensure that is installed on your system.

## Project mappings

Key mappings are available automatically within `.csproj` and `.fsproj` files

### Add reference

`<leader>ar` -> Opens a picker for selecting which project reference to add

![image](https://github.com/user-attachments/assets/dec096be-8a87-4dd8-aaec-8c22849d1640)

### Package autocomplete

When editing package references inside a .csproject file it is possible to enable autocomplete.
This will trigger autocomplete for `<PackageReference Include="<cmp-trigger>" Version="<cmp-trigger>" />`
This functionality relies on `jq` so ensure that is installed on your system.

#### Using nvim-cmp

```lua
    cmp.register_source("easy-dotnet", require("easy-dotnet").package_completion_source)
    ...
    sources = cmp.config.sources({
        { name = 'nvim_lsp'    },
        { name = 'easy-dotnet' },
        ...
    }),
    ...
```

#### Using Blink.cmp
```lua
return {
  "saghen/blink.cmp",
  version = "*",
  config = function()
    require("blink.cmp").setup {
      fuzzy = { implementation = "prefer_rust_with_warning" },
      sources = {
        default = { "lsp", "easy-dotnet", "path" },
        providers = {
          ["easy-dotnet"] = {
            name = "easy-dotnet",
            enabled = true,
            module = "easy-dotnet.completion.blink",
            score_offset = 10000,
            async = true,
          },
        },
      },
    }
  end,
}
```

![image](https://github.com/user-attachments/assets/81809aa8-704b-4481-9445-3985ddef6c98)

>[!NOTE]
>Latest is added as a snippet to make it easier to select the latest version

![image](https://github.com/user-attachments/assets/2b59735f-941e-44d2-93cf-76b13ac3e76f)


## .NET Framework
Basic support for .NET framework has been achieved. This means basic functionality like `build/run/test/test-runner` should work. If you find something not working feel free to file an issue.

### Requirements
- `choco install nuget.commandline`
- Visual studio installation
- `options.server.use_visual_studio == true`

## New
Create dotnet templates as with `dotnet new <templatename>`
Try it out by running `Dotnet new`

### Project
https://github.com/user-attachments/assets/aa067c17-3611-4490-afc8-41d98a526729

### Configuration file

If a configuration file is selected it will
1. Create the configuration file and place it next to your solution file. (solution files and gitignore files are placed in cwd)

### Integrating with nvim-tree

Adding the following configuration to your nvim-tree will allow for creating files using dotnet templates

```lua
    require("nvim-tree").setup({
      on_attach = function(bufnr)
        local api = require('nvim-tree.api')

        local function opts(desc)
          return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
        end

        vim.keymap.set('n', 'A', function()
          local node = api.tree.get_node_under_cursor()
          local path = node.type == "directory" and node.absolute_path or vim.fs.dirname(node.absolute_path)
          require("easy-dotnet").create_new_item(path)
        end, opts('Create file from dotnet template'))
      end
    })
```

### Integrating with neo-tree
Adding the following configuration to your neo-tree will allow for creating files using dotnet templates

```lua
      require("neo-tree").setup({
      ---...other options
        filesystem = {
          window = {
            mappings = {
              -- Make the mapping anything you want
              ["R"] = "easy",
            },
          },
          commands = {
            ["easy"] = function(state)
              local node = state.tree:get_node()
              local path = node.type == "directory" and node.path or vim.fs.dirname(node.path)
              require("easy-dotnet").create_new_item(path, function()
                require("neo-tree.sources.manager").refresh(state.name)
              end)
            end
          }
        },
      })
```

### Integrating with mini files

Adding the following autocmd to your config will allow for creating files using dotnet templates

```lua
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniFilesBufferCreate",
      callback = function(args)
        local buf_id = args.data.buf_id
        vim.keymap.set("n", "<leader>a", function()
          local entry = require("mini.files").get_fs_entry()
          if entry == nil then
            vim.notify("No fd entry in mini files", vim.log.levels.WARN)
            return
          end
          local target_dir = entry.path
          if entry.fs_type == "file" then
            target_dir = vim.fn.fnamemodify(entry.path, ":h")
          end
          require("easy-dotnet").create_new_item(target_dir)
        end, { buffer = buf_id, desc = "Create file from dotnet template" })
      end,
    })
```

### Integrating with snacks explorer

```lua
  {
    "folke/snacks.nvim",
    ---@type snacks.Config
    opts = {
      picker = {
        sources = {
          explorer = {
            win = {
              list = {
                keys = {
                  ["A"] = "explorer_add_dotnet",
                },
              },
            },
            actions = {
              explorer_add_dotnet = function(picker)
                local dir = picker:dir()
                local easydotnet = require("easy-dotnet")

                easydotnet.create_new_item(dir, function(item_path)
                  local tree = require("snacks.explorer.tree")
                  local actions = require("snacks.explorer.actions")
                  tree:open(dir)
                  tree:refresh(dir)
                  actions.update(picker, { target = item_path })
                  picker:focus()
                end)
              end,
            },
          },
        },
      },
    },
  },

```

## EntityFramework
Common EntityFramework commands have been added mainly to reduce the overhead of writing `--project .. --startup-project ..`. 

### Requirements
This functionality relies on dotnet-ef tool, install using `dotnet tool install --global dotnet-ef`

### Database
- `Dotnet ef database update`
- `Dotnet ef database update pick` --allows to pick which migration to apply
- `Dotnet ef database drop`

### Migrations
- `Dotnet ef migrations add <name>`
- `Dotnet ef migrations remove`
- `Dotnet ef migrations list`


## Language injections

[Rider-like](https://www.jetbrains.com/help/rider/Language_Injections.html#use-comments) 
syntax highlighting for injected languages (sql, json and xml) based on comments.

Just add single-line comment like `//language=json` before string to start using this.

### Showcase 

Language injection with raw json string as an example.

![image](https://github.com/user-attachments/assets/2057bf66-e207-479c-8bd9-35714cdb7e24)

### Requirements

This functionality is based on [Treesitter](https://github.com/nvim-treesitter/nvim-treesitter) 
and parsers for `sql`, `json` and `xml`, so make sure you have these parsers installed: `:TSInstall sql json xml`.

### Support matrix

#### Strings

| string          | sql | json | xml |
|-----------------|-----|------|-----|
| quoted          | ✅  | ❌   | ✅  |
| verbatim        | ✅  | ❌   | ✅  |
| raw             | ✅  | ✅   | ✅  |
| regexp quoted   | ❌  | ❌   | ❌  |
| regexp verbatim | ❌  | ❌   | ❌  |
| regexp raw      | ❌  | ❌   | ❌  |

#### Interpolated strings

| interpolated string | json | xml |
|---------------------|------|-----|
| quoted              | ❌   | ❌  |
| verbatim            | ❌   | ❌  |
| raw                 | ✅   | ✅  |
| regexp quoted       | ❌   | ❌  |
| regexp verbatim     | ❌   | ❌  |
| regexp raw          | ❌   | ❌  |

## Nvim-dap configuration

Check out [debugging-setup](./docs/debugging.md) for a full walkthrough of debugging setup

## Troubleshooting

- Update the plugin to latest version
- Run `:checkhealth easy-dotnet`

## Highlight groups

<details>
<summary>Click to see all highlight groups</summary>

<!--hl start-->

| Highlight group                         | Default            |
| --------------------------------------- | ------------------ |
| **EasyDotnetTestRunnerSolution**        | *Question*         |
| **EasyDotnetTestRunnerProject**         | *Character*        |
| **EasyDotnetTestRunnerTest**            | *Normal*           |
| **EasyDotnetTestRunnerSubcase**         | *Conceal*           |
| **EasyDotnetTestRunnerDir**             | *Directory*        |
| **EasyDotnetTestRunnerPackage**         | *Include*          |
| **EasyDotnetTestRunnerPassed**          | *DiagnosticOk*     |
| **EasyDotnetTestRunnerFailed**          | *DiagnosticError*  |
| **EasyDotnetTestRunnerRunning**         | *DiagnosticWarn*   |
| **EasyDotnetDebuggerFloatVariable**     | *Question*         |
| **EasyDotnetDebuggerVirtualVariable**   | *Question*         |
| **EasyDotnetDebuggerVirtualException**  | *DiagnosticError*         |
<!-- hl-end -->

</details>



