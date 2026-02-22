# Debugging in .NET

This guide describes how to integrate .NET Core debugging in Neovim using nvim-dap and netcoredbg.

## Table of Contents

* [Debugging in .NET](#debugging-in-.net)
  * [Setting up .NET Debugging with nvim-dap and netcoredbg](#setting-up-.net-debugging-with-nvim-dap-and-netcoredbg)
    * [Debugging](#debugging)
    * [Configuration](#configuration)
    * [Interactive Console & External Terminal](#interactive-console--external-terminal)
    * [Programmatic Debugging](#programmatic-debugging)
    * [CPU/MEM Performance Widgets](#cpumem-performance-widgets)

## Debugging
To start debugging do the following. Ensure you have configured the code below

Dont start the project before doing this, debugger has to start it for you

1. Open any `.cs` file in the project
2. Set a breakpoint with `<leader>b`
3. Press `<F5>`
4. Select the project you want to debug (if your breakpoint is in a library you have to select the entry point project)
5. Wait for breakpoint to be hit
6. You can now `<F10>` step over, `<F11>` step into, `<F5>` continue and more (see code)

## Configuration

```lua
--lazy.nvim
--nvim-dap config
return {
  "mfussenegger/nvim-dap",
  config = function()
    local dap = require "dap"

    -- Keymaps for controlling the debugger
    vim.keymap.set("n", "q", function()
      dap.terminate()
      dap.clear_breakpoints()
    end, { desc = "Terminate and clear breakpoints" })

    vim.keymap.set("n", "<F5>", dap.continue, { desc = "Start/continue debugging" })
    vim.keymap.set("n", "<F10>", dap.step_over, { desc = "Step over" })
    vim.keymap.set("n", "<F11>", dap.step_into, { desc = "Step into" })
    vim.keymap.set("n", "<F12>", dap.step_out, { desc = "Step out" })
    vim.keymap.set("n", "<leader>b", dap.toggle_breakpoint, { desc = "Toggle breakpoint" })
    vim.keymap.set("n", "<leader>dO", dap.step_over, { desc = "Step over (alt)" })
    vim.keymap.set("n", "<leader>dC", dap.run_to_cursor, { desc = "Run to cursor" })
    vim.keymap.set("n", "<leader>dr", dap.repl.toggle, { desc = "Toggle DAP REPL" })
    vim.keymap.set("n", "<leader>dj", dap.down, { desc = "Go down stack frame" })
    vim.keymap.set("n", "<leader>dk", dap.up, { desc = "Go up stack frame" })

    end
}
```

## Interactive Console & External Terminal

`easy-dotnet` fully supports interactive console debugging (e.g., `Console.ReadLine()`). You can control where your target application runs using the `debugger.console` option in your `easy-dotnet` setup:

1. **`integratedTerminal` (Default):** Runs the application inside a Neovim buffer or the `nvim-dap-ui` console widget. This keeps everything inside your editor and prevents your application's standard output from cluttering the DAP REPL.
2. **`externalTerminal`:** Spawns a completely detached OS terminal window (similar to hitting F5 in Visual Studio).

### External Terminal Configuration Examples

If you choose to use an `externalTerminal`, you must tell `nvim-dap` which terminal emulator to use on your machine. You can configure this globally in your Neovim configuration:

```lua
local dap = require("dap")

-- Windows Terminal (Windows)
dap.defaults.fallback.external_terminal = {
  command = "wt",
  args = { "-w", "0", "nt", "--" },
}

-- Kitty (Linux/macOS)
dap.defaults.fallback.external_terminal = {
  command = "kitty",
  args = { "--hold" }, 
}

-- Alacritty (Linux/macOS)
dap.defaults.fallback.external_terminal = {
  command = "alacritty",
  args = { "-e" }, 
}

```

## Programmatic Debugging

You can bind a key just like `<F5>` / Run in Visual Studio that triggers debugging for the default project or a selected profile.
```lua
vim.keymap.set("n", "<C-p>", function()
  vim.cmd "Dotnet debug default profile"
end, { nowait = true, desc = "Start debugging" })
```

## CPU/MEM Performance Widgets

easy-dotnet.nvim provides real-time performance monitoring during debug sessions through two custom dapui widgets: `easy-dotnet_cpu` and `easy-dotnet_mem`. These widgets display live CPU usage (percentage) and memory consumption (bytes) of your debugged application.

### Features
- **CPU Widget**: Shows real-time CPU percentage utilization
- **Memory Widget**: Displays current memory usage in bytes
- **Live Updates**: Automatically refreshes during active debug sessions

### Configuration Example

Add the widgets to your dapui layout configuration:
```lua
local dapui = require("dapui")

dapui.setup {
  layouts = {
    {
      elements = {
        { id = "easy-dotnet_cpu", size = 0.5 },  -- CPU usage panel (50% of layout)
        { id = "easy-dotnet_mem", size = 0.5 },  -- Memory usage panel (50% of layout)
      },
      size = 35,      -- Width of the sidebar
      position = "right",
    },
  },
}
```

### Preview

The widgets integrate seamlessly into your debug UI, providing at-a-glance performance metrics:

<img width="1152" height="810" alt="image" src="https://github.com/user-attachments/assets/70ebc04d-921e-4ed2-aa98-c642885b56ff" />
