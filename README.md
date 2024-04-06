# Easy-dotnet.nvim

## Motivation

I wrote this plugin because I couldnt find any plugin that seems to seem this problem. Coming from Rider I was used to being able to just press a single button to run the project. Running projects using the terminal is easy but in bigger projects you usually have to write something like this `dotnet run --project src/AwesomeProject.Api`

## Features

- [x] Solution support
- [x] Csproj support
- [ ] Actions
    - [x] Build
    - [x] Run
    - [x] Test
    - [x] Restore
- [x] Get dll for debugging
- [x] Resolve different types of projects
    - [x] Web
    - [x] Test
    - [x] Console
- [ ] .Net user secrets
    - [x] Open user-secrets in a buffer
    - [ ] Create new user-secrets

## Setup
```lua
-- lazy.nvim
return {
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = { "nvim-lua/plenary.nvim", 'nvim-telescope/telescope.nvim', },
  config = function()
    local dotnet = require("easy-dotnet")
    -- Options are not required
    dotnet.setup({
      ---@param action "test"|"restore"|"build"|"run"
      terminal = function(path, action)
        local commands = {
          run = function(path)
            return "dotnet run --project " .. path
          end,
          test = function(path)
            return "dotnet test " .. path
          end,
          restore = function(path)
            return "dotnet restore " .. path
          end,
          build = function(path)
            return "dotnet build " .. path
          end
        }
        local command = commands[action](path) .. "\r"
        vim.cmd('term')
        vim.cmd('startinsert!')
        vim.api.nvim_feedkeys(string.format("%s", command), 'n', true)
      end,
      secrets = {
        on_select = function(selectedItem)
          local home_dir = vim.fn.expand('~')
          if require("easy-dotnet.extensions").isWindows() then
            local secret_path = home_dir ..
                '\\AppData\\Roaming\\Microsoft\\UserSecrets\\' .. selectedItem.secrets .. "\\secrets.json"
            vim.cmd("edit " .. vim.fn.fnameescape(secret_path))
          else
            local secret_path = home_dir .. "/.microsoft/usersecrets/" .. selectedItem.secrets .. "/secrets.json"
            vim.cmd("edit " .. vim.fn.fnameescape(secret_path))
          end
        end
      },
    })

    vim.api.nvim_create_user_command('Secrets', function()
      dotnet.secrets()
    end, {})

    vim.keymap.set("n", "<C-p>", function()
      dotnet.run_project()
    end)
  end
}
```


## Contributions

I mainly created this project for my own use-case but I would love to help others. If you have any good ideas for this project create an issue describing the enchancement.


