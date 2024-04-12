# Easy-dotnet.nvim
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

## Motivation

I wrote this plugin because I could not find any plugin that solved my problem. Coming from Rider I was used to being able to just press a single button to run the project. Running projects using the terminal is easy but in bigger projects you usually have to write something like this `dotnet run --project src/AwesomeProject.Api`
When I started using neovim as my daily driver I missed a lot of features. Like editing user-secrets for a project. This plugin aims to make it easy to work with dotnet in Neovim.

## Features

- [x] Solution support
- [x] Csproj support
- [x] Actions
    - [x] Build
    - [x] Run
    - [x] Test
    - [x] Restore
- [x] Get dll for debugging
- [x] Resolve different types of projects
    - [x] Web
    - [x] Test
    - [x] Console
- [x] Resolve target-framework of project
- [x] .Net user secrets
    - [x] Open user-secrets in a buffer
    - [x] Create new user-secrets
    - [x] Secrets preview in picker

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

dotnet.test_project() -- Runs dotnet test in the project. If there are multiple a telescope picker opens
dotnet.test_solution() -- Runs dotnet test in the solution/csproj
dotnet.run_project() -- Runs dotnet run in the project. If there are multiple a telescope picker opens
dotnet.restore() -- Runs dotnet restore for the solution/csproj file
dotnet.secrets() -- Opens .Net user-secrets in a new buffer for you to edit
dotnet.build() -- Runs dotnet build in the project. If there are multiple a telescope picker opens
dotnet.build_solution() -- Runs dotnet build in the solution
dotnet.get_debug_dll() -- Returns the dll from the bin/debug folder. If there are multiple projects a telescope picker opens
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

I mainly created this project for my own use-case but I would love to help others. If you have any good ideas for this project create an issue describing the enchancement.


