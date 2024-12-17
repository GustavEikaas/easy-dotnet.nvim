# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

> 💡 **Tip:** 
> This plugin and all its features should work for both **C#** and **F#**.

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
5. [Setup](#setup)
   - [Without options](#without-options)
   - [With options](#with-options)
6. [Commands](#commands)
   - [Lua functions](#lua-functions)
   - [Vim commands](#vim-commands)
7. [Testrunner](#testrunner)
   - [Keymaps](#keymaps)
   - [Debugging tests](#debugging-tests)
   - [Running tests from buffer](#running-tests-directly-from-buffer)
   - [Debugging tests from buffer](#debugging-tests-directly-from-buffer)
8. [Outdated](#outdated)
   - [Requirements](#requirements)
9. [Project mappings](#project-mappings)
   - [Add reference](#add-reference)
   - [Package autocomplete](#package-autocomplete)
10. [New](#new)
    - [Project](#project)
    - [Configuration file](#configuration-file)
    - [Integrating with nvim-tree](#integrating-with-nvim-tree)
11. [EntityFramework](#entityframework)
    - [Database](#database)
    - [Migrations](#migrations)
12. [Language injections](#language-injections)
    - [Showcase](#showcase)
    - [Requirements](#requirements-2)
    - [Support matrix](#support-matrix)
13. [Nvim-dap configuration](#nvim-dap-configuration)
    - [Basic example](#basic-example)
    - [Advanced example](#advanced-example)
14. [Advanced configurations](#advanced-configurations)
    - [Overseer](#overseer)

## Features

- Solution, csproj and fsproj support: Whether its a single project or a solution containing multiple projects easy-dotnet has you covered.
- Action Commands: Execute common tasks like building, running, testing, cleaning and restoring with ease.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Debugging Helpers: While easy-dotnet.nvim doesn't set up DAP (Debugger Adapter Protocol) for you, it provides useful helper functions for debugging. These include resolving the DLL you are debugging and rebuilding before launching DAP, ensuring a smooth debugging experience.
- Test runner: Test runner similiar to the one you find in Rider.
- Outdated command: Makes checking outdated packages a breeze using virtual text
- (csproj/fsproj) mappings: Keymappings for .csproj and .fsproj files are automatically available
- Auto bootstrap namespace: Automatically inserts namespace when opening a newly created `.cs` file
- Create dotnet templates like with `dotnet new`, automatically adding them to the current solution
- Package autocomplete inside .csproj and .fsproj files [Check it out](#package-autocomplete)
- [Rider-like](https://www.jetbrains.com/help/rider/Language_Injections.html#use-comments)
syntax highlighting for injected languages (sql, json and xml) based on comments

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
      --Optional function to return the path for the dotnet sdk (e.g C:/ProgramFiles/dotnet/sdk/8.0.0)
      -- easy-dotnet will resolve the path automatically if this argument is omitted, for a performance improvement you can add a function that returns a hardcoded string
      get_sdk_path = get_sdk_path,
      ---@type TestRunnerOptions
      test_runner = {
        ---@type "split" | "float" | "buf"
        viewmode = "float",
        enable_buffer_test_execution = true, --Experimental, run tests directly from buffer
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
        --- Optional table of extra args e.g "--blame crash"
        additional_args = {}
      },
      ---@param action "test" | "restore" | "build" | "run"
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

        local command = commands[action]() .. "\r"
        vim.cmd("vsplit")
        vim.cmd("term " .. command)
      end,
      secrets = {
        path = get_secret_path
      },
      csproj_mappings = true,
      fsproj_mappings = true,
      auto_bootstrap_namespace = true
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
| `dotnet.build_quickfix()` | `dotnet build <TS> <DArgs>` and opens build errors in the quickfix list |
| `dotnet.build_default()` | `dotnet build <TS Default> <DArgs>` |
| `dotnet.build_default_quickfix()` | `dotnet build <TS Default> <DArgs>` and opens build errors in the quickfix list |
||
| `dotnet.test()` | `dotnet test <TS> <DArgs>` |
| `dotnet.test_solution()` | `dotnet test <TS> <DArgs>` |
| `dotnet.test_default()` | `dotnet test <TS Default> <DArgs>` |
||
| `dotnet.restore()` | `dotnet restore <sln> <Dargs>` |
| `dotnet.clean()`                              | `dotnet clean <sln> <DArgs>`                                                                          |
||
| `dotnet.testrunner()`                         | Shows or hides the testrunner                                                                                            |
| `dotnet.testrunner_refresh()`                 | Refreshes the testrunner                                                                                                          |
| `dotnet.testrunner_refresh_build()`           | Builds the sln, then refreshes the testrunner                                                                                   |
||
| `dotnet.is_dotnet_project()`                  | Returns `true` if a `.csproj` or `.sln` file is present in the current working directory or subfolders       |
| `dotnet.try_get_selected_solution()`          | If a solution is selected, returns `{ basename: string, path: string }`, otherwise `nil`                    |
| `dotnet.new()`                                | Telescope picker for creating a new template based on `Dotnet new`                                                                                                            |
| `dotnet.outdated()`                           | Runs `Dotnet outdated` in supported file types (`.csproj`, `.fsproj`, `Directory.Packages.props`, `Packages.props`) and displays virtual text with the latest package versions. |
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
| `dotnet.ef_database_update_pick()`            |  Opens a Telescope picker to update the database to a selected migration.                                                                                                          |
||
| `dotnet.createfile(path)`                     | Spawns a Telescope picker for creating a new file based on a `.NET new` template                            |
| `dotnet.secrets()`                            | Opens Telescope picker for `.NET user-secrets`                                                              |
| `dotnet.get_debug_dll()`                      | Returns the DLL from the `bin/debug` folder                                                                 |
| `dotnet.get_environment_variables(project_name, project_path)` | Returns the environment variables from the `launchSetting.json` file                                         |
| `dotnet.reset()`                              | Deletes all files persisted by `easy-dotnet.nvim`. Use this if unable to pick a different solution or project |


```lua
local dotnet = require("easy-dotnet")
dotnet.get_environment_variables(project_name, project_path
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
dotnet.build_quickfix()                 
dotnet.build_default()                 
dotnet.build_default_quickfix()       
dotnet.run()
dotnet.run_profile_default()
dotnet.run_default()
dotnet.secrets()                                                          
dotnet.clean()                                                           
dotnet.restore()                   
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
Dotnet test
Dotnet test default
Dotnet test solution
Dotnet build
Dotnet build quickfix
Dotnet build solution
Dotnet build default
Dotnet build default quickfix
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
Dotnet reset
```

Certain commands like Dotnet test|run|build also supports passing some selected additional arguments like.
```
Dotnet run|test|build --no-build --no-restore -c prerelease
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


## Outdated

Run the command `Dotnet outdated` in one of the supported filetypes, virtual text with packages latest version will appear

Supports the following filetypes

- *.csproj
- *.fsproj
- Directory.Packages.props
- Packages.props


![image](https://github.com/user-attachments/assets/496caec1-a18b-487a-8a37-07c4bb9fa113)

### Requirements
This functionality relies on dotnet-outdated-tool, install using `dotnet tool install -g dotnet-outdated-tool`

## Project mappings

Key mappings are available automatically within `.csproj` and `.fsproj` files

### Add reference
`<leader>ar` -> Opens a telescope picker for selecting which project reference to add

![image](https://github.com/user-attachments/assets/dec096be-8a87-4dd8-aaec-8c22849d1640)

### Package autocomplete
When editing package references inside a .csproject file it is possible to enable autocomplete.
This will trigger autocomplete for `<PackageReference Include="<cmp-trigger>" Version="<cmp-trigger>" />`
This functionality relies on `jq` so ensure that is installed on your system.

Using nvim-cmp
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
![image](https://github.com/user-attachments/assets/81809aa8-704b-4481-9445-3985ddef6c98)

>[!NOTE]
>Latest is added as a snippet to make it easier to select the latest version

![image](https://github.com/user-attachments/assets/2b59735f-941e-44d2-93cf-76b13ac3e76f)

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

While its out of the scope of this plugin to setup dap, we do provide a few helpful functions to make it easier.

### Basic example

```lua
local M = {}

--- Rebuilds the project before starting the debug session
---@param co thread
local function rebuild_project(co, path)
  local spinner = require("easy-dotnet.ui-modules.spinner").new()
  spinner:start_spinner("Building")
  vim.fn.jobstart(string.format("dotnet build %s", path), {
    on_exit = function(_, return_code)
      if return_code == 0 then
        spinner:stop_spinner("Built successfully")
      else
        spinner:stop_spinner("Build failed with exit code " .. return_code, vim.log.levels.ERROR)
        error("Build failed")
      end
      coroutine.resume(co)
    end,
  })
  coroutine.yield()
end

M.register_net_dap = function()
  local dap = require("dap")
  local dotnet = require("easy-dotnet")
  local debug_dll = nil

  local function ensure_dll()
    if debug_dll ~= nil then
      return debug_dll
    end
    local dll = dotnet.get_debug_dll()
    debug_dll = dll
    return dll
  end

  for _, value in ipairs({ "cs", "fsharp" }) do
    dap.configurations[value] = {
      {
        type = "coreclr",
        name = "launch - netcoredbg",
        request = "launch",
        env = function()
          local dll = ensure_dll()
          local vars = dotnet.get_environment_variables(dll.project_name, dll.relative_project_path)
          return vars or nil
        end,
        program = function()
          local dll = ensure_dll()
          local co = coroutine.running()
          rebuild_project(co, dll.project_path)
          return dll.relative_dll_path
        end,
        cwd = function()
          local dll = ensure_dll()
          return dll.relative_project_path
        end,

      }
    }
  end

  dap.listeners.before['event_terminated']['easy-dotnet'] = function()
    debug_dll = nil
  end

  dap.adapters.coreclr = {
    type = "executable",
    command = "netcoredbg",
    args = { "--interpreter=vscode" },
  }
end

return M
```

For profiles to be read it must contain a profile with the name of your csproject
The file is expected to be in the Properties/launchsettings.json relative to your .csproject file
```json
{
  "profiles": {
    "NeovimDebugProject.Api": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "launchUrl": "swagger",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      },
      "applicationUrl": "https://localhost:7073;http://localhost:7071"
    }
}
```

### Advanced example

Dependencies:
- which-key
- overseer
- netcoredbg
- dap
- easy-dotnet

**Overseer template:**

```lua
local tmpl = {
  name = "Build .NET App With Spinner",
  builder = function(params)
    local logPath = vim.fn.stdpath("data") .. "/easy-dotnet/build.log"
    function filter_warnings(line)
      if not line:find("warning") then
        return line:match("^(.+)%((%d+),(%d+)%)%: (.+)$")
      end
    end
    return {
      name = "build",
      cmd = "dotnet build /flp:v=q /flp:logfile=" .. logPath,
      components = {
        { "on_complete_dispose", timeout = 30 },
        "default",
        "show_spinner",
        { "unique", replace = true },
        {
          "on_output_parse",
          parser = {
            diagnostics = {
              { "extract", filter_warnings, "filename", "lnum", "col", "text" },
            },
          },
        },
        {
          "on_result_diagnostics_quickfix",
          open = true,
          close = true,
        },
      },
      cwd = require("easy-dotnet").get_debug_dll().relative_project_path,
    }
  end,
}
return tmpl

```

**Overseer component**
```lua
return {
  desc = "Show Spinner",
  -- Define parameters that can be passed in to the component
  -- The params passed in will match the params defined above
  constructor = function(params)
    local num = 0
    local spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }

    local notification = vim.notify(spinner_frames[1] .. " Building", "info", {
      timeout = false,
    })

    local timer = vim.loop.new_timer()

    return {
      on_init = function(self, task)
        timer:start(
          100,
          100,
          vim.schedule_wrap(function()
            num = num + 1
            local new_spinner = num % #spinner_frames
            notification =
              vim.notify(spinner_frames[new_spinner + 1] .. " Building", "info", { replace = notification })
          end)
        )
      end,
      on_complete = function(self, task, code)
        vim.notify("", "info", { replace = notification, timeout = 1 })
        timer:stop()
        return code
      end,
    }
  end,
}

```

**Dap Config**

```lua
return {
  {
    "mfussenegger/nvim-dap",
    opts = function(_, opts)
      local dap = require("dap")
      if not dap.adapters["netcoredbg"] then
        require("dap").adapters["netcoredbg"] = {
          type = "executable",
          command = vim.fn.exepath("netcoredbg"),
          args = { "--interpreter=vscode" },
          -- console = "internalConsole",
        }
      end

      local dotnet = require("easy-dotnet")
      local debug_dll = nil
      local function ensure_dll()
        if debug_dll ~= nil then
          return debug_dll
        end
        local dll = dotnet.get_debug_dll()
        debug_dll = dll
        return dll
      end

      for _, lang in ipairs({ "cs", "fsharp", "vb" }) do
        dap.configurations[lang] = {
          {
            log_level = "DEBUG",
            type = "netcoredbg",
            justMyCode = false,
            stopAtEntry = false,
            name = "Default",
            request = "launch",
            env = function()
              local dll = ensure_dll()
              local vars = dotnet.get_environment_variables(dll.project_name, dll.relative_project_path)
              return vars or nil
            end,
            program = function()
              require("overseer").enable_dap()
              local dll = ensure_dll()
              return dll.relative_dll_path
            end,
            cwd = function()
              local dll = ensure_dll()
              return dll.relative_project_path
            end,
            preLaunchTask = "Build .NET App With Spinner",
          },
        }

        dap.listeners.before["event_terminated"]["easy-dotnet"] = function()
          debug_dll = nil
        end
      end
    end,
    keys = {
      { "<leader>d", "", desc = "+debug", mode = { "n", "v" } },
      -- HYDRA MODE
      -- NOTE: the delay is set to prevent the which-key hints to appear
      {
        "<leader>d<space>",
        function()
          require("which-key").show({ delay = 1000000000, keys = "<leader>d", loop = true })
        end,
        desc = "DAP Hydra Mode (which-key)",
      },
      {
        "<leader>dR",
        function()
          local dap = require("dap")
          local extension = vim.fn.expand("%:e")
          dap.run(dap.configurations[extension][1])
        end,
        desc = "Run default configuration",
      },
      {
        "<leader>dB",
        function()
          require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
        end,
        desc = "Breakpoint Condition",
      },
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle Breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "Continue",
      },
      {
        "<leader>da",
        function()
          require("dap").continue({ before = get_args })
        end,
        desc = "Run with Args",
      },
      {
        "<leader>dC",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Run to Cursor",
      },
      {
        "<leader>dg",
        function()
          require("dap").goto_()
        end,
        desc = "Go to Line (No Execute)",
      },
      {
        "<leader>di",
        function()
          require("dap").step_into()
        end,
        desc = "Step Into",
      },
      {
        "<leader>dj",
        function()
          require("dap").down()
        end,
        desc = "Down",
      },
      {
        "<leader>dk",
        function()
          require("dap").up()
        end,
        desc = "Up",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_last()
        end,
        desc = "Run Last",
      },
      {
        "<leader>do",
        function()
          require("dap").step_out()
        end,
        desc = "Step Out",
      },
      {
        "<leader>dO",
        function()
          require("dap").step_over()
        end,
        desc = "Step Over",
      },
      {
        "<leader>dp",
        function()
          require("dap").pause()
        end,
        desc = "Pause",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.toggle()
        end,
        desc = "Toggle REPL",
      },
      {
        "<leader>ds",
        function()
          require("dap").session()
        end,
        desc = "Session",
      },
      {
        "<leader>dt",
        function()
          require("dap").terminate()
        end,
        desc = "Terminate",
      },
      {
        "<leader>dw",
        function()
          require("dap.ui.widgets").hover()
        end,
        desc = "Widgets",
      },
    },
  },
}

```


## Advanced configurations

### Overseer
Thanks to [franroa](https://github.com/franroa) for sharing his configuration with the community

- It watches the run and test commands
- It creates a list of tasks to have a history
- other things that can be configured with overseer, like running those tasks in the order you want
- If used with resession, the tasks are run automatically on opening the project (this is specially interesting if you have errors in your build and have to leave the coding session. It will pop up the quickfix list in the next day)

```lua
return {
  {
    "GustavEikaas/easy-dotnet.nvim",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
    config = function()
      local logPath = vim.fn.stdpath("data") .. "/easy-dotnet/build.log"
      local dotnet = require("easy-dotnet")

      dotnet.setup({
        terminal = function(path, action)
          local commands = {
            run = function()
              return "dotnet run --project " .. path
            end,
            test = function()
              return "dotnet test " .. path
            end,
            restore = function()
              return "dotnet restore --configfile " .. os.getenv("NUGET_CONFIG") .. " " .. path
            end,
            build = function()
              return "dotnet build  " .. path .. " /flp:v=q /flp:logfile=" .. logPath
            end,
          }

          local function filter_warnings(line)
            if not line:find("warning") then
              return line:match("^(.+)%((%d+),(%d+)%)%: (.+)$")
            end
          end

          local overseer_components = {
            { "on_complete_dispose", timeout = 30 },
            "default",
            { "unique", replace = true },
            {
              "on_output_parse",
              parser = {
                diagnostics = {
                  { "extract", filter_warnings, "filename", "lnum", "col", "text" },
                },
              },
            },
            {
              "on_result_diagnostics_quickfix",
              open = true,
              close = true,
            },
          }

          if action == "run" or action == "test" then
            table.insert(overseer_components, { "restart_on_save", paths = { LazyVim.root.git() } })
          end

          local command = commands[action]()
          local task = require("overseer").new_task({
            strategy = {
              "toggleterm",
              use_shell = false,
              direction = "horizontal",
              open_on_start = false,
            },
            name = action,
            cmd = command,
            cwd = LazyVim.root.git(),
            components = overseer_components,
          })
          task:start()
        end
      })
    end,
  },
}

```

## Highlight groups

<details>
<summary>Click to see all highlight groups</summary>

<!--hl start-->

| Highlight group                  | Default            |
| -------------------------------- | ------------------ |
| **EasyDotnetTestRunnerSolution** | *Question*         |
| **EasyDotnetTestRunnerProject**  | *Character*        |
| **EasyDotnetTestRunnerTest**     | *Normal*           |
| **EasyDotnetTestRunnerSubcase**  | *Conceal*           |
| **EasyDotnetTestRunnerDir**      | *Directory*        |
| **EasyDotnetTestRunnerPackage**  | *Include*          |
| **EasyDotnetTestRunnerPassed**   | *DiagnosticOk*     |
| **EasyDotnetTestRunnerFailed**   | *DiagnosticError*  |
| **EasyDotnetTestRunnerRunning**  | *DiagnosticWarn*   |

<!-- hl-end -->

</details>


## Signs

<details>
<summary>Click to see all signs</summary>

<!--sign start-->

  ```lua
  --override example
  vim.fn.sign_define("EasyDotnetTestSign", { text = "", texthl = "Character" })
  ```

| Sign                           | Highlight                    |
| ------------------------------ | ---------------------------- |
| **EasyDotnetTestSign**         | Character                    |
| **EasyDotnetTestPassed**       | EasyDotnetTestRunnerPassed   |
| **EasyDotnetTestFailed**       | EasyDotnetTestRunnerFailed   |
| **EasyDotnetTestSkipped**      | (none)                       |
| **EasyDotnetTestError**        | EasyDotnetTestRunnerFailed   |

<!-- sign-end -->

</details>

