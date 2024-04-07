# Easy-dotnet.nvim

## Motivation

I wrote this plugin because I couldnt find any plugin that seems to seem this problem. Coming from Rider I was used to being able to just press a single button to run the project. Running projects using the terminal is easy but in bigger projects you usually have to write something like this `dotnet run --project src/AwesomeProject.Api`

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
```lua
-- lazy.nvim
return {
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

```lua
local dotnet = require("easy-dotnet")

dotnet.test_project()
dotnet.test_solution()
dotnet.run_project()
dotnet.restore()
dotnet.secrets()
dotnet.build()
dotnet.build_solution()
dotnet.get_debug_dll()
```

```
-- Supports tabcompletion after Dotnet
Dotnet run
Dotnet test
Dotnet restore
Dotnet build
Dotnet secrets
```

## Contributions

I mainly created this project for my own use-case but I would love to help others. If you have any good ideas for this project create an issue describing the enchancement.


