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
- Action Commands: Execute common tasks like building, running, testing, and restoring with ease.
- Project Type Resolution: Detect and handle different project types, including web, test, and console applications.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Debugging Helpers: While easy-dotnet.nvim doesn't set up DAP (Debugger Adapter Protocol) for you, it provides useful helper functions for debugging. These include resolving the DLL you are debugging and rebuilding before launching DAP, ensuring a smooth debugging experience.

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
        vim.cmd('term')
        vim.cmd('startinsert!')
        vim.api.nvim_feedkeys(string.format("%s", command), 'n', true)
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
dotnet.get_debug_dll()      -- Return the dll from the bin/debug folder
```

### Vim commands
```
Dotnet run
Dotnet test
Dotnet restore
Dotnet build
Dotnet secrets
```

## Contributions
While I initially developed this plugin to fulfill my own needs, I'm open to contributions and suggestions from the community. If you have any ideas or enhancements in mind, feel free to create an issue and let's discuss how we can make easy-dotnet.nvim even better!


