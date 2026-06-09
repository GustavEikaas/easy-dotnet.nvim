# Advanced Patterns

This guide shows a more complete setup for users who want an IDE-like .NET workflow in Neovim. It focuses on external run/debug windows, the built-in terminal panel, lualine status, and project-file language features.

## Visual Studio-style run and debug

`external_terminal` controls where easy-dotnet launches applications for `:Dotnet run`. When `debugger.console = "externalTerminal"` is also set, debug sessions use the same external terminal style.

easy-dotnet runs external applications through AppWrapper. AppWrapper keeps an external terminal process around and reuses idle windows for later run/debug sessions, so repeated launches do not create a pile of terminal windows.

Choose the terminal command for the OS and terminal you use:

```lua
-- Windows Terminal
local external_terminal = {
  command = "wt",
  args = { "-w", "-1", "nt", "--" },
}

-- Kitty
-- local external_terminal = {
--   command = "kitty",
--   args = { "--hold", "--" },
-- }
```

## Full setup example

```lua
-- lazy.nvim
local external_terminal = {
  command = "wt",
  args = { "-w", "-1", "nt", "--" },
}

return {
  "GustavEikaas/easy-dotnet.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
    "mfussenegger/nvim-dap",
  },
  config = function()
    local dotnet = require("easy-dotnet")

    dotnet.setup({
      external_terminal = external_terminal,
      debugger = {
        console = "externalTerminal",
      },
      notifications = {
        handler = false,
      },
      lsp = {
        restart_roslyn_on_branch_change = true,
      },
      auto_bootstrap_namespace = {
        type = "file_scoped",
        enabled = true,
      },
    })

    vim.keymap.set("n", "<A-t>", function()
      vim.cmd("Dotnet testrunner")
    end, { nowait = true, desc = "Toggle testrunner" })

    vim.keymap.set("n", "<C-A-p>", function()
      vim.cmd("Dotnet debug profile default")
    end, { nowait = true, desc = "Debug with default launchprofile" })

    vim.keymap.set("n", "<C-p>", function()
      vim.cmd("Dotnet run profile default")
    end, { nowait = true, desc = "Run with default launchprofile" })

    vim.keymap.set("n", "<C-b>", function()
      dotnet.build_default_quickfix()
    end, { nowait = true, desc = "Build default project/solution" })

    vim.keymap.set({ "n", "t" }, "<A-i>", function()
      vim.cmd("Dotnet terminal toggle")
    end, { noremap = true, silent = true, desc = "Toggle terminal" })
  end,
}
```

With this setup:

- `:Dotnet run` and `:Dotnet run profile default` launch in the configured external terminal.
- `:Dotnet debug profile default` launches the application in the external terminal and attaches the debugger.
- Finished external applications leave the AppWrapper window available for reuse.
- easy-dotnet notifications are suppressed because lualine shows job and run state.

## Built-in terminal panel

The `:Dotnet terminal` commands open a VS Code-inspired terminal panel inside Neovim:

```vim
:Dotnet terminal toggle
:Dotnet terminal show
:Dotnet terminal hide
```

The panel is separate from `external_terminal`. Use it for editor-owned terminal tabs and plugin command output you want to keep inside Neovim. The default mappings support switching tabs, creating a user terminal, closing the current tab, and hiding the panel.

When `managed_terminal.auto_hide = true`, successful plugin-owned commands hide the panel after `managed_terminal.auto_hide_delay` milliseconds. User-created terminals stay available as normal terminal tabs.

## Quick create menu

The quick create menu creates contextual C# items without leaving the current explorer location. It is designed for file explorer integrations where the selected directory becomes the output path.

Call the Lua helper from explorer mappings:

```lua
require("easy-dotnet").create_item(path)
```

The menu is backed by the easy-dotnet server and currently creates C# enums, records, interfaces, and classes using Roslyn. It also respects `auto_bootstrap_namespace.type`: when that option is set to `"file_scoped"`, generated C# items prefer file-scoped namespaces.

When integrating with file explorers, pass the selected directory as `path`. If the cursor is on a file, use the file's parent directory:

```lua
local target_dir = node.type == "directory" and node.absolute_path or vim.fs.dirname(node.absolute_path)
require("easy-dotnet").create_item(target_dir)
```

## Lualine status

Disabling `notifications.handler` when lualine shows active jobs and run/debug state:

```lua
local dotnet = require("easy-dotnet")

require("lualine").setup({
  sections = {
    lualine_a = {
      "mode",
      dotnet.lualine.jobs,
    },
    lualine_x = {
      dotnet.lualine.active_project,
      {
        dotnet.lualine.run_status,
        color = dotnet.lualine.run_status_color,
        on_click = dotnet.lualine.run_status_click,
      },
    },
  },
})
```

`dotnet.lualine.jobs` reports server and command progress. `dotnet.lualine.active_project` shows the selected startup project and launch profile. `dotnet.lualine.run_status` can run, debug, or stop the active project through its click handler.

## ProjX LSP

ProjX LSP is enabled by default and improves `.csproj` editing. It is separate from Roslyn C# LSP and focuses on project-file intelligence.

Useful ProjX features include:

- Package and version autocomplete in `PackageReference` elements.
- Formatting for project XML.
- Code actions for sorting package references, converting target framework elements, removing package or project references, opening user secrets, and expanding or collapsing XML elements.
- Definitions for project references, imports, and user secrets where supported.
