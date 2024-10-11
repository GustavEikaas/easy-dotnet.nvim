# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

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
8. [Outdated](#outdated)
   - [Requirements](#requirements)
9. [Csproj mappings](#csproj-mappings)
   - [Add reference](#add-reference)
   - [Package autocomplete](#package-autocomplete)
10. [New](#new)
    - [Project](#project)
    - [Configuration file](#configuration-file)
11. [EntityFramework](#entityframework)
    - [Database](#database)
    - [Migrations](#migrations)
12. [Nvim-dap configuration](#nvim-dap-configuration)
    - [Basic example](#basic-example)
    - [Advanced example](#advanced-example)
13. [Advanced configurations](#advanced-configurations)
    - [Overseer](#overseer)

## Features

- Solution and Csproj Support: Seamlessly work with entire solutions or individual projects.
- Action Commands: Execute common tasks like building, running, testing, cleaning and restoring with ease.
- Project Type Resolution: Detect and handle different project types, including web, test, and console applications.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Debugging Helpers: While easy-dotnet.nvim doesn't set up DAP (Debugger Adapter Protocol) for you, it provides useful helper functions for debugging. These include resolving the DLL you are debugging and rebuilding before launching DAP, ensuring a smooth debugging experience.
- Test runner: Test runner similiar to the one you find in Rider.
- Outdated command: Makes checking outdated packages a breeze using virtual text
- Csproj mappings: Keymappings for .csproj files are automatically available
- Create dotnet templates like with `dotnet new`
- Package autocomplete inside .csproj files [Check it out](#package-autocomplete)

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
      get_sdk_path = get_sdk_path,
      ---@type TestRunnerOptions
      test_runner = {
        ---@type "split" | "float" | "buf"
        viewmode = "split",
        enable_buffer_test_execution = false, --Experimental, run tests directly from buffer
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
        --- Optional table of extra args e.g "--blame crash"
        additional_args = {}
      },
      ---@param action "test" | "restore" | "build" | "run"
      terminal = function(path, action)
        local commands = {
          run = function()
            return "dotnet run --project " .. path
          end,
          test = function()
            return "dotnet test " .. path
          end,
          restore = function()
            return "dotnet restore " .. path
          end,
          build = function()
            return "dotnet build " .. path
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

```lua
local dotnet = require("easy-dotnet")
dotnet.test_project()                               -- Run dotnet test in the project
dotnet.test_default()                               -- Run dotnet test in the last selected project
dotnet.test_solution()                              -- Run dotnet test in the solution/csproj
dotnet.run_project()                                -- Run dotnet run in the project
dotnet.run_with_profile(true)                       -- Run dotnet run with a specific launch profile, true/false will run with last selected profile and project
dotnet.run_default()                                -- Run dotnet run in the last selected project
dotnet.restore()                                    -- Run dotnet restore for the solution/csproj file
dotnet.secrets()                                    -- Open .NET user-secrets in a new buffer for editing
dotnet.build()                                      -- Run dotnet build in the project
dotnet.build_default()                              -- Will build the last selected project
dotnet.build_solution()                             -- Run dotnet build in the solution
dotnet.build_quickfix(dotnet_args?: string)         -- Build dotnet project and open build errors in quickfix list
dotnet.build_default_quickfix(dotnet_args?: string) -- Will build the last selected project and open build errors in quickfix list
dotnet.clean()                                      -- Run dotnet clean in the project
dotnet.get_debug_dll()                              -- Return the dll from the bin/debug folder
dotnet.is_dotnet_project()                          -- Returns true if a csproject or sln file is present in cwd or some folders down
```

### Vim commands
```
Dotnet run 
Dotnet test 
Dotnet restore
Dotnet build 
Dotnet clean
Dotnet secrets
Dotnet testrunner
Dotnet outdated
Dotnet new
```

Certain commands like Dotnet test|run|build also supports passing some selected additional arguments like.

```
Dotnet run|test|build --no-build --no-restore -c prerelease
```

## Testrunner

Integrated test runner inspired by Rider IDE
![image](https://github.com/user-attachments/assets/0f9396ac-6827-4edf-b063-a178ea09a2b2)
![image](https://github.com/user-attachments/assets/5fd297c6-7df5-4cf5-9ba7-5a196e8f24ee)

- [x] Basic test runner window
  - [x] Grouped by namespace
  - [x] Passed, skipped, failed
  - [x] Unit test name
  - [x] Collapsable hieararchy 
  - [x] Peek stack trace
  - [x] Run sln,project,namespace,test
  - [x] Aggregate test results
  - [x] Go to file (only for failed tests)

### Keymaps
- `W` -> Collapse all
- `E` -> Expand all
- `o` -> Expand/collapse under cursor
- `<leader>r` -> Run test under cursor
- `<leader>d` -> `[Experimental]` Debug test under cursor using nvim-dap
- `<leader>R` -> Run all tests
- `<leader>p` -> Peek stacktrace on failed test
- `<leader>fe` -> Show only failed tests
- `<leader>gf` -> Go to file (only works inside stacktrace float)
- `g` -> Go to file
- `q` -> Close window

### Debugging tests
Using the keybinding `<leader>d` will set a breakpoint in the test and launch nvim-dap

https://github.com/user-attachments/assets/b56891c9-1b65-4522-8057-43eff3d1102d

## Outdated

Run the command `Dotnet outdated` in a .csproj file, virtual text with packages latest version will appear

![image](https://github.com/user-attachments/assets/496caec1-a18b-487a-8a37-07c4bb9fa113)

### Requirements
This functionality relies on dotnet-outdated-tool, install using `dotnet tool install -g dotnet-outdated-tool`

## Csproj mappings

Key mappings are available automatically within `.csproj` files

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

