# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

## Motivation
As a developer transitioning from Rider to Neovim, I found myself missing the simplicity of running projects with just a single button click. Tired of typing out lengthy terminal commands for common tasks like running, testing, and managing user secrets, I decided to create easy-dotnet.nvim. This plugin aims to bridge the gap between the convenience of IDEs like Rider and the flexibility of Neovim.

---

# Table of Contents

1. [Easy-dotnet.nvim](#easy-dotnetnvim)
2. [Simplifying .NET development in Neovim](#simplifying-net-development-in-neovim)
3. [Motivation](#motivation)
4. [Features](#features)
   - [Solution and Csproj Support](#solution-and-csproj-support)
   - [Action Commands](#action-commands)
   - [Project Type Resolution](#project-type-resolution)
   - [User Secrets Management](#user-secrets-management)
   - [Debugging Helpers](#debugging-helpers)
   - [Test runner](#test-runner)
   - [Outdated command](#outdated-command)
   - [Csproj mappings](#csproj-mappings)
   - [Create dotnet templates like with `dotnet new`](#create-dotnet-templates-like-with-dotnet-new)
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
11. [Advanced configurations](#advanced-configurations)
    - [Overseer](#overseer)

---

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


