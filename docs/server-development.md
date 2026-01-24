## Server Development Guide

This guide explains how to run and test the server locally during development.

### Overview

The easy-dotnet.nvim plugin communicates with the Easy Dotnet Server via named pipes using JSON-RPC. During normal operation, the server generates a unique pipe name for each instance. For local development, we use a **static pipe name** to make debugging easier.

### Local Development Setup

#### 1. Configure Static Pipe Name

In `./lua/easy-dotnet/rpc/rpc.lua`, there's a commented line that hardcodes the pipe name:
```lua
function M.get_pipe_path(pipe_name)
  -- Uncomment this line for local development:
  -- pipe_name = "EasyDotnet_ROcrjwn9kiox3tKvRWcQg"
  
  if extensions.isWindows() then
    return [[\\.\pipe\]] .. pipe_name
  else
    return get_tmpdir() .. "CoreFxPipe_" .. pipe_name
  end
end
```

**Uncomment** the `pipe_name = "EasyDotnet_ROcrjwn9kiox3tKvRWcQg"` line.

#### 2. Start the Server

Run the server locally from your development environment:
```bash
dotnet run --project EasyDotnet.IDE
```

The server will listen on the static pipe name.

#### 3. Connect from Neovim

With the static pipe name uncommented in the client code, start Neovim and use any easy-dotnet command. You should see output in the server console:
```
Client connected to pipe: EasyDotnet_ROcrjwn9kiox3tKvRWcQg
```

### Important Limitations When Running Locally

#### Bundled Resources Are Not Available

The production distribution bundles Roslyn LSP and netcoredbg within the .NET tool package. These **are not available** when running the server locally from source.

#### netcoredbg (Debugger)

⚠️ **Requires manual configuration**

Since the bundled debugger isn't available locally, you must provide a custom path using **one of these methods**:

**Option 1: Neovim Configuration**

```lua
require("easy-dotnet").setup({
  debugger = {
    bin_path = "/path/to/netcoredbg" -- or netcoredbg.exe on Windows
  }
})
```

**Option 2: Environment Variable**

```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
export EASY_DOTNET_DEBUGGER_BIN_PATH="/path/to/netcoredbg"
```

