# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Simplifying .NET development in Neovim
Are you a .NET developer looking to harness the power of Neovim for your daily coding tasks? Look no further! easy-dotnet.nvim is here to streamline your workflow and make .NET development in Neovim a breeze.

## Motivation
As a developer transitioning from Rider to Neovim, I found myself missing the simplicity of running projects with just a single button click. Tired of typing out lengthy terminal commands for common tasks like running, testing, and managing user secrets, I decided to create easy-dotnet.nvim. This plugin aims to bridge the gap between the convenience of IDEs like Rider and the flexibility of Neovim.

## Features

- Solution and Csproj Support: Seamlessly work with entire solutions or individual projects.
- Action Commands: Execute common tasks like building, running, testing, cleaning and restoring with ease.
- Project Type Resolution: Detect and handle different project types, including web, test, and console applications.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Debugging Helpers: While easy-dotnet.nvim doesn't set up DAP (Debugger Adapter Protocol) for you, it provides useful helper functions for debugging. These include resolving the DLL you are debugging and rebuilding before launching DAP, ensuring a smooth debugging experience.
- Test runner: Test runner similiar to the one you find in Rider.
- Outdated command: Makes checking outdated packages a breeze using virtual text

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
dotnet.test_project()       -- Run dotnet test in the project
dotnet.test_solution()      -- Run dotnet test in the solution/csproj
dotnet.run_project()        -- Run dotnet run in the project
dotnet.restore()            -- Run dotnet restore for the solution/csproj file
dotnet.secrets()            -- Open .NET user-secrets in a new buffer for editing
dotnet.build()              -- Run dotnet build in the project
dotnet.build_solution()     -- Run dotnet build in the solution
dotnet.build_quickfix()     -- Build dotnet project and open build errors in quickfix list
dotnet.clean()              -- Run dotnet clean in the project
dotnet.get_debug_dll()      -- Return the dll from the bin/debug folder
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

Run the command Dotnet outdated in a .csproj file, virtual text with packages latest version will appear

![image](https://github.com/user-attachments/assets/496caec1-a18b-487a-8a37-07c4bb9fa113)

### Requirements
This functionality relies on dotnet-outdated-tool, install using `dotnet tool install -g dotnet-outdated-tool`

## Contributions
While I initially developed this plugin to fulfill my own needs, I'm open to contributions and suggestions from the community. If you have any ideas or enhancements in mind, feel free to create an issue and let's discuss how we can make easy-dotnet.nvim even better!


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


