[![Typing SVG](https://readme-typing-svg.demolab.com?font=Fira+Code&size=32&pause=1000&width=435&lines=easy-dotnet.nvim)](https://git.io/typing-svg)
<a href="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim">
	<img src="https://dotfyle.com/plugins/GustavEikaas/easy-dotnet.nvim/shield?style=flat" />
</a>

<a href="https://discord.gg/HkAyDy2hWU">
  <img src="https://img.shields.io/badge/Discord-Join%20easy--dotnet-5865F2?logo=discord&logoColor=white&style=for-the-badge" alt="Join easy-dotnet on Discord">
</a>

## Simplifying .NET development in Neovim
easy-dotnet.nvim brings common .NET IDE workflows into Neovim: run, debug, test, manage packages, work with solutions, use Roslyn LSP, and handle project files without leaving the editor.

>[!IMPORTANT]
>This plugin now uses [easy-dotnet-server](https://github.com/GustavEikaas/easy-dotnet-server) to enable more advanced functionality. As a result, the server may require more frequent updates.
>Run `:Dotnet _server update` or `dotnet tool install -g EasyDotnet` to update it.
>The plugin will attempt to detect when the server is outdated and notify you. If you encounter any issues, please don't hesitate to file an issue.

> 📰 **Stay updated:** Major updates and new features are announced in [`news.md`](./news.md).  
> Give it a read periodically to stay in sync with the latest capabilities!


## Motivation
As a developer transitioning from Rider to Neovim, I found myself missing the simplicity of running projects with just a single button click. Tired of typing out lengthy terminal commands for common tasks like running, testing, and managing user secrets, I decided to create easy-dotnet.nvim. This plugin aims to bridge the gap between the convenience of IDEs like Rider and the flexibility of Neovim.

## Table of Contents

1. [Simplifying .NET development in Neovim](#simplifying-net-development-in-neovim)
2. [Motivation](#motivation)
3. [Features](#features)
4. [Requirements](#requirements)
5. [Setup](#setup)
   - [Without options](#without-options)
   - [With options](#with-options)
   - [Lualine config](#lualine-config)
6. [Advanced Patterns](#advanced-patterns)
7. [Commands](#commands)
8. [Roslyn LSP](#roslyn-lsp)
9. [Test runner](#test-runner)
   - [Keymaps](#keymaps)
   - [Debugging tests](#debugging-tests)
   - [Running tests from buffer](#running-tests-from-buffer)
10. [Neotest](#neotest)
   - [Requirements](#requirements-1)
   - [Setup](#setup-1)
11. [Workspace Diagnostics](#workspace-diagnostics)
    - [Commands](#commands-1)
    - [Configuration](#configuration)
    - [Features](#features-1)
12. [Outdated](#outdated)
13. [Add](#add)
    - [Add package](#add-package)
14. [Project mappings](#project-mappings)
    - [Add reference](#add-reference)
    - [Package autocomplete](#package-autocomplete)
15. [.NET Framework](#net-framework)
    - [Requirements](#requirements-2)
16. [New](#new)
    - [Project](#project)
    - [Configuration file](#configuration-file)
    - [Integrating with nvim-tree](#integrating-with-nvim-tree)
    - [Integrating with neo-tree](#integrating-with-neo-tree)
    - [Integrating with mini files](#integrating-with-mini-files)
    - [Integrating with snacks explorer](#integrating-with-snacks-explorer)
17. [EntityFramework](#entityframework)
    - [Requirements](#requirements-3)
    - [Database](#database)
    - [Migrations](#migrations)
18. [Language injections](#language-injections)
    - [Showcase](#showcase)
    - [Requirements](#requirements-4)
    - [Support matrix](#support-matrix)
19. [Nvim-dap configuration](#nvim-dap-configuration)
20. [Troubleshooting](#troubleshooting)
21. [Highlight groups](#highlight-groups)
22. [Local Development](#local-development)
23. [Star History](#star-history)
24. [Contributors](#contributors)

## Features

- Roslyn LSP support out of the box — powered by the official .NET Roslyn language server (see [LSP details](./docs/lsp.md))
- Debugger configured out of the box - choose between bundled [netcoredbg](https://github.com/samsung/netcoredbg), [dncdbg](https://github.com/viewizard/dncdbg) and [sharpdbg](https://github.com/MattParkerDev/sharpdbg) engines
- Solution, slnx, csproj and fsproj support: Whether its a single project or a solution containing multiple projects easy-dotnet has you covered.
- Action Commands: Execute common tasks like building, running, testing, cleaning and restoring with ease.
- User Secrets Management: Edit, create, and preview .NET user secrets directly within Neovim.
- Test runner: Test runner similiar to the one you find in Rider.
- Workspace diagnostics: Get diagnostic errors and warnings from your entire solution or individual projects
- Outdated command: Makes checking outdated packages a breeze using virtual text
- (csproj/fsproj) mappings: Keymappings for .csproj and .fsproj files are automatically available
- Auto bootstrap namespace: Automatically inserts namespace and class/interface when opening a newly created `.cs` file. (also checks clipboard for json to create class from)
- Create dotnet templates like with `dotnet new`, automatically adding them to the current solution
- Package autocomplete inside .csproj and .fsproj files [Check it out](#package-autocomplete)
- [Rider-like](https://www.jetbrains.com/help/rider/Language_Injections.html#use-comments)
syntax highlighting for injected languages (sql, json and xml) based on comments

## Requirements

- Neovim 0.11+ built with **LuaJIT**
- [EasyDotnet](https://www.nuget.org/packages/EasyDotnet) `dotnet tool install -g EasyDotnet`

Although not *required* by the plugin, it is highly recommended to install one of:
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [snacks.nvim](https://github.com/folke/snacks.nvim)

## Setup

### Without options
```lua
-- lazy.nvim
{
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = { "nvim-lua/plenary.nvim", 'folke/snacks.nvim', },
  config = function()
    require("easy-dotnet").setup()
  end
}
```

### With options

All options are optional. [docs/configuration.md](./docs/configuration.md) lists every option with its default value, all keymaps and highlight groups.

```lua
-- lazy.nvim
{
  "GustavEikaas/easy-dotnet.nvim",
  -- 'nvim-telescope/telescope.nvim' or 'ibhagwan/fzf-lua' or 'folke/snacks.nvim'
  -- are highly recommended for a better experience
  dependencies = { "nvim-lua/plenary.nvim", 'mfussenegger/nvim-dap', 'folke/snacks.nvim', },
  config = function()
    local dotnet = require("easy-dotnet")
    dotnet.setup({
      picker = "snacks",
      test_runner = {
        viewmode = "vsplit",
      },
      lsp = {
        easy_dotnet_extension_enabled = true,
        enhanced_rename = true,
      },
    })

    -- Example command
    vim.api.nvim_create_user_command('Secrets', function()
      dotnet.secrets()
    end, {})

    -- Example keybinding
    vim.keymap.set("n", "<C-p>", function()
      vim.cmd("Dotnet run profile default")
    end)
  end
}
```

### Lualine config

#### Simple components

```lua
local dotnet = require("easy-dotnet")

require("lualine").setup {
  sections = {
    -- ...
    lualine_a = { "mode", dotnet.lualine.jobs },
    -- Shows the default startup project and its launch profile (if any),
    -- pushed by the server whenever it changes.
    lualine_x = { dotnet.lualine.active_project },
    -- ...
  },
}
```

#### Dynamic run/stop component

A single component that adapts to running state:

- **Idle:** ` ProjectName` — left-click runs, right-click debugs
- **Running:** ` ProjectName` (green) — process alive, no debugger attached
- **Debugging:** ` ProjectName` (orange) — debugger attached

Uses three [Codicons](https://www.nerdfonts.com/) (requires Nerd Font): `nf-cod-debug_start`, `nf-cod-debug_stop`, `nf-cod-debug`.

```lua
local dotnet = require("easy-dotnet")

require("lualine").setup {
  sections = {
    lualine_x = {
      dotnet.lualine.jobs,
      {
        dotnet.lualine.run_status,
        color    = dotnet.lualine.run_status_color,
        on_click = dotnet.lualine.run_status_click,
      },
    },
  },
}
```

## Advanced Patterns

For a more complete Visual Studio-style setup with external run/debug terminals, AppWrapper window reuse, the built-in terminal panel, lualine status, and ProjX project-file features, see [Advanced Patterns](./docs/advanced-patterns.md).

## Commands

All `:Dotnet` commands and their Lua equivalents (e.g. `require("easy-dotnet").build()`) are listed in [docs/commands.md](./docs/commands.md). Run `:Dotnet` without arguments to pick a command.

## Roslyn LSP

Roslyn LSP support is enabled **out of the box** — no configuration required.  
Just open a C#, Razor, or CSHTML file and the official .NET language server starts automatically.
If `roslyn-language-server` is missing, easy-dotnet will install the global tool with `dotnet tool install --global roslyn-language-server --prerelease`.
Existing installs are not updated automatically; run `dotnet-easydotnet roslyn update` when an update is suggested.

This dotnet tool exists at two places:
  * [nuget.org], which is not updated that often.
  * [Azure Devops feed], where updates happen multiple times a day.

> [!IMPORTANT]  
> The version used in vscode can be extracted [here](https://github.com/dotnet/vscode-csharp/blob/main/package.json#L43).  
> The extension uses the [Azure Devops feed] as well.

 ```bash
  # Installing the tool using the more recent Azure Devops feed
  dotnet tool install -g roslyn-language-server --prerelease --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json

  # Installing the tool from nuget.org
  dotnet tool install -g roslyn-language-server --prerelease

  # Updating works the same way as installing ( by replacing "install" with "update")
  dotnet tool update -g roslyn-language-server --prerelease --source https://pkgs.dev.azure.com/azure-public/vside/_packaging/vs-impl/nuget/v3/index.json
  ```

Razor support also uses VS Code's HTML language server for markup completions, hover, formatting, and related requests.
easy-dotnet does **not** bundle or auto-install this Node dependency.
Install it globally with `npm install -g vscode-langservers-extracted`, or per project with `npm install --save-dev vscode-langservers-extracted`.
When `vscode-html-language-server` is available in project `node_modules/.bin` or on `PATH`, easy-dotnet starts and wires it up automatically.
Run `:checkhealth easy-dotnet` for dependency status and install guidance.
Set `lsp.razor.html.cmd` to override the command, or disable Razor with `lsp.razor.enabled = false`.

Set `lsp.restart_roslyn_on_branch_change = true` to restart Roslyn automatically after Git branch or detached HEAD changes. This can help when large file watcher bursts leave stale diagnostics, especially on Linux. It is disabled by default because it stops and starts the Roslyn client for the active root.

For more information [check out](./docs/lsp.md)

## Test runner

Integrated test runner inspired by Rider IDE. Powered by [easy-dotnet-server](https://github.com/GustavEikaas/easy-dotnet-server).
The server supports both VSTest and Microsoft Testing Platform adapters.

<img width="1911" height="1049" alt="testrunner float" src="https://github.com/user-attachments/assets/f50ba57a-34bf-4a79-8c35-f44f1ef02dc0" />
<img width="1879" height="1051" alt="testrunner mid-run" src="https://github.com/user-attachments/assets/39f1c14c-965b-4cef-914e-0d4ca44f12f8" />

If you experience issues with a test adapter please open an issue.

The test runner starts automatically when the server starts and runs discovery silently in the background, so the tree is ready before you open the window.

- [x] Test runner window
  - [x] Float, split and vsplit view modes
  - [x] Grouped by solution, project, namespace and class
  - [x] Jump to next / previous failing test (`]f` / `[f`, dot-repeatable)
  - [x] Passed, skipped, failed with live counts in header
  - [x] Configurable icons and highlights
  - [x] Collapsible hierarchy
  - [x] Peek stacktrace with parsed highlighting (your code in yellow, framework code in grey)
  - [x] Run and debug from solution, project, namespace, class or test
  - [x] Cancel in-flight runs
  - [x] Go to file
  - [x] Aggregate test results across projects
- [x] Buffer integration
  - [x] Gutter signs on test methods and classes
  - [x] Run test or class from buffer
  - [x] Debug test or class from buffer
  - [x] Peek stacktrace from buffer
  - [x] Flash on run and result

### Keymaps

The runner window and test files have their own keymaps. See [Keymaps](./docs/configuration.md#keymaps) for the defaults and how to override them.

### Debugging tests

Use `<leader>d` on any node in the runner to start a debug session. Breakpoints must be set manually before starting the session.

### Run settings

Use `:Dotnet test run-settings set` to pick a `.runsettings` file for a project. The server searches the workspace, stores the selection per project, and applies it when running tests through the VSTest adapter.

### Running tests from buffer

Gutter signs appear automatically on test methods and classes once discovery has completed.

Run, debug or peek the stack trace of the test or class under the cursor with the [test file keymaps](./docs/configuration.md#test-files).

When a run is triggered from the buffer the method or class flashes to confirm it was picked up. When the run finishes it flashes again in the colour of the result.

<img width="1238" height="575" alt="test signs" src="https://github.com/user-attachments/assets/9e6e2d96-b389-4b35-b2a1-c8392ffdbcba" />
<img width="1228" height="578" alt="test flash confirm" src="https://github.com/user-attachments/assets/bcb8377a-577f-4808-a20e-1c90f884d9d4" />
<img width="1885" height="1044" alt="floating stacktrace from buffer" src="https://github.com/user-attachments/assets/109fdfdd-d93b-400e-a4e0-8ebf41ff9312" />

## Neotest

easy-dotnet ships a built-in [neotest](https://github.com/nvim-neotest/neotest) adapter. It reuses the same test runner state that powers the built-in test runner window, so no extra discovery step is needed.

### Requirements

- [nvim-neotest/neotest](https://github.com/nvim-neotest/neotest)

### Setup

**1. Enable `neotest_integration` in easy-dotnet**

This disables the built-in buffer signs and keymaps so neotest can manage them instead:

```lua
require("easy-dotnet").setup({
  test_runner = {
    neotest_integration = true,
  },
})
```

**2. Register the adapter with neotest**

```lua
require("neotest").setup({
  adapters = {
    require("easy-dotnet.neotest"),
  },
})
```

#### lazy.nvim example

```lua
{
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-lua/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "GustavEikaas/easy-dotnet.nvim",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("easy-dotnet.neotest"),
      },
    })
  end,
},
-- Make sure easy-dotnet is configured with neotest_integration = true
{
  "GustavEikaas/easy-dotnet.nvim",
  config = function()
    require("easy-dotnet").setup({
      test_runner = {
        neotest_integration = true,
      },
    })
  end,
}
```

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

After running `Dotnet outdated`, buffer-local keymaps are registered to upgrade packages in place
(replaces the `Version="..."` attribute with the latest version and removes the virtual text).
Both keymaps are configurable via `outdated.mappings`:

| Default     | Action                                       |
| ----------- | -------------------------------------------- |
| `<leader>pu` | Upgrade the outdated package under the cursor |
| `<leader>pa` | Upgrade all outdated packages in the buffer   |


![image](https://github.com/user-attachments/assets/496caec1-a18b-487a-8a37-07c4bb9fa113)

## Add

### Add package

Adding nuget packages are available using the `:Dotnet add package` command. This will allow you to browse for nuget packages.

![image](https://github.com/user-attachments/assets/00a9d38a-6afe-42ec-b971-04191fee1d59)

## Project mappings

Key mappings are available automatically within `.csproj` and `.fsproj` files

### Add reference

`<leader>ar` -> Opens a picker for selecting which project reference to add

![image](https://github.com/user-attachments/assets/dec096be-8a87-4dd8-aaec-8c22849d1640)

### Package autocomplete

Package autocomplete in `.csproj` files is provided by the ProjX LSP, which is enabled by default.
This triggers autocomplete for `<PackageReference Include="<lsp-trigger>" Version="<lsp-trigger>" />`.

Older configurations that manually register the `easy-dotnet` source with `nvim-cmp` or `blink.cmp` should be removed.

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

Adding the following configuration to your nvim-tree will allow for quickly creating contextual items. Today this creates C# enums, records, interfaces, and classes using Roslyn.

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
          require("easy-dotnet").create_item(path)
        end, opts('Create item'))
      end
    })
```

### Integrating with neo-tree
Adding the following configuration to your neo-tree will allow for quickly creating contextual items. Today this creates C# enums, records, interfaces, and classes using Roslyn.

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
              require("easy-dotnet").create_item(path)
            end
          }
        },
      })
```

### Integrating with mini files

Adding the following autocmd to your config will allow for quickly creating contextual items.

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
          require("easy-dotnet").create_item(target_dir)
        end, { buffer = buf_id, desc = "Create item" })
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

                easydotnet.create_item(dir)
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

All highlight groups and their defaults are listed in [docs/configuration.md](./docs/configuration.md#highlight-groups).

### Inactive preprocessor branches (`#if DEBUG`)

Roslyn reports code inside inactive preprocessor branches — for example a `#if DEBUG` block while
the build configuration is `Release` — as an off-spec `excludedCode` semantic token. Neovim only
links the standard LSP token types by default, so easy-dotnet links this one for you:

| Highlight group | Default |
| --- | --- |
| **@lsp.type.excludedCode** | *Comment* |

It is set with `default = true`, so your colorscheme or config wins. To pick your own look:

```lua
vim.api.nvim_set_hl(0, "@lsp.type.excludedCode", { link = "NonText" })
```

Or to turn the dimming off entirely:

```lua
vim.api.nvim_set_hl(0, "@lsp.type.excludedCode", {})
```

Put it in a `ColorScheme` autocmd if your colorscheme is loaded after easy-dotnet.

## Local Development

Check out [setup guide](./docs/server-development.md)

## Star History

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=GustavEikaas/easy-dotnet.nvim&type=date&theme=dark&legend=top-left" />
  <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=GustavEikaas/easy-dotnet.nvim&type=date&legend=top-left" />
  <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=GustavEikaas/easy-dotnet.nvim&type=date&legend=top-left" />
</picture>

## Contributors
<a href="https://github.com/GustavEikaas/easy-dotnet.nvim/graphs/contributors">
<img src="https://contrib.rocks/image?repo=GustavEikaas/easy-dotnet.nvim" />
</a>


[nuget.org]: https://www.nuget.org/packages/roslyn-language-server
[Azure Devops feed]: https://dev.azure.com/azure-public/vside/_artifacts/feed/vs-impl/NuGet/roslyn-language-server.linux-x64
