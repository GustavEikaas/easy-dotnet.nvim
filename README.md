# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

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
10. [New](#new)
    - [Project](#project)
    - [Configuration file](#configuration-file)
11. [Nvim-dap configuration](#nvim-dap-configuration)
    - [Basic example](#basic-example)
    - [Advanced example](#advanced-example)
12. [Advanced configurations](#advanced-configurations)
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

## Setup

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
      test_runner = {
        noBuild = true,
        noRestore = true,
      },
      ---@param action "test"|"restore"|"build"|"run"
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
dotnet.test_project()                       -- Run dotnet test in the project
dotnet.test_default()                       -- Run dotnet test in the last selected project
dotnet.test_solution()                      -- Run dotnet test in the solution/csproj
dotnet.run_project()                        -- Run dotnet run in the project
dotnet.run_default()                        -- Run dotnet run in the last selected project
dotnet.restore()                            -- Run dotnet restore for the solution/csproj file
dotnet.secrets()                            -- Open .NET user-secrets in a new buffer for editing
dotnet.build()                              -- Run dotnet build in the project
dotnet.build_default()                      -- Will build the last selected project
dotnet.build_solution()                     -- Run dotnet build in the solution
dotnet.build_quickfix()                     -- Build dotnet project and open build errors in quickfix list
dotnet.build_default_quickfix()             -- Will build the last selected project and open build errors in quickfix list
dotnet.clean()                              -- Run dotnet clean in the project
dotnet.get_debug_dll()                      -- Return the dll from the bin/debug folder
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


## Testrunner

Integrated test runner inspired by Rider IDE
![image](https://github.com/user-attachments/assets/27955253-cb41-4f47-8586-2b4d068ec538)

- [x] Basic test runner window
  - [x] Grouped by namespace
  - [x] Passed, skipped, failed
  - [x] Unit test name
  - [x] Collapsable hieararchy 
  - [x] Peek stack trace
- [x] Resolve test results from selected test scope

### Keymaps
- `W` -> Collapse all
- `E` -> Expand all
- `o` -> Expand/collapse under cursor
- `<leader>r` -> Run test under cursor
- `<leader>R` -> Run all tests
- `<leader>p` -> Peek stacktrace on failed test
- `<leader>fe` -> Show only failed tests

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

## New
Create dotnet templates as with `dotnet new <templatename>`
Try it out by running `Dotnet new`

### Project
https://github.com/user-attachments/assets/aa067c17-3611-4490-afc8-41d98a526729

### Configuration file

If a configuration file is selected it will
1. Create the configuration file and place it next to your solution file. (solution files and gitignore files are placed in cwd)


## Nvim-dap configuration

While its out of the scope of this plugin to setup dap, we do provide a few helpful functions to make it easier.

### Basic example

```lua
local M = {}

--- Rebuilds the project before starting the debug session
---@param co thread
local function rebuild_project(co, path)
  vim.notify("Building project")
  vim.fn.jobstart(string.format("dotnet build %s", path), {
    on_exit = function(_, return_code)
      if return_code == 0 then
        vim.notify("Built successfully")
      else
        vim.notify("Build failed with exit code " .. return_code)
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

  dap.configurations.cs = {
    {
      type = "coreclr",
      name = "launch - netcoredbg",
      request = "launch",
      env = function()
        local dll = ensure_dll()
        -- Reads the launchsettingsjson file looking for a profile with the name of your project
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

```
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
```
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

```
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

## Advanced example

### Dependencies:
- overseer (for the preLaunchTask)
- which-key (with hydra mode)
- easy-dotnet (path resolution)

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
        }
      end
      for _, lang in ipairs({ "cs", "fsharp", "vb" }) do
        local debug_dll = nil
        dap.configurations[lang] = {
          {
            log_level = "DEBUG",
            type = "netcoredbg",
            justMyCode = false,
            stopAtEntry = false,
            name = "Default",
            request = "launch",
            env = {
              ASPNETCORE_ENVIRONMENT = function()
                return "Development"
              end,
              ASPNETCORE_URLS = function()
                return "https://localhost:5005;http://localhost:5006"
              end,
            },
            ---@diagnostic disable-next-line: redundant-parameter
            program = function()
              require("overseer").enable_dap()
              debug_dll = require("easy-dotnet").get_debug_dll()
              return vim.fn.getcwd() .. "/" .. debug_dll.project_path .. debug_dll.dll_path
            end,
            cwd = function()
              return vim.fn.getcwd() .. "/" .. debug_dll.project_path
            end,
            preLaunchTask = "Build .NET App", -- custom overseer task
          },
        }
        -- end
      end
    end,
    keys = {
      {
        "<leader>d<space>",
        function()
         -- NOTE: the delay is set to prevent the which-key hints to appear
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

```
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




