# Debugging in .NET

This guide describes how to integrate .NET Core debugging in Neovim using nvim-dap and netcoredbg.

## Table of Contents

* [Debugging in .NET](#debugging-in-.net)
  * [Setting up .NET Debugging with nvim-dap and netcoredbg](#setting-up-.net-debugging-with-nvim-dap-and-netcoredbg)
    * [Debugging](#debugging)
    * [Configuration](#configuration)
    * [Variables Viewer](#variables-viewer)
    * [Debugging with launch-profiles](#debugging-with-launch-profiles)

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

local function rebuild_project(co, path)
  local spinner = require("easy-dotnet.ui-modules.spinner").new()
  spinner:start_spinner "Building"
  vim.fn.jobstart(string.format("dotnet build %s", path), {
    on_exit = function(_, return_code)
      if return_code == 0 then
        spinner:stop_spinner "Built successfully"
      else
        spinner:stop_spinner("Build failed with exit code " .. return_code, vim.log.levels.ERROR)
        error "Build failed"
      end
      coroutine.resume(co)
    end,
  })
  coroutine.yield()
end

--lazy.nvim
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

    -- .NET specific setup using `easy-dotnet`
    require("easy-dotnet.netcoredbg").register_dap_variables_viewer() -- special variables viewer specific for .NET
    local dotnet = require("easy-dotnet")
    local debug_dll = nil

    local function ensure_dll()
      if debug_dll ~= nil then
        return debug_dll
      end
      local dll = dotnet.get_debug_dll(true)
      debug_dll = dll
      return dll
    end

    for _, value in ipairs({ "cs", "fsharp" }) do
      dap.configurations[value] = {
        {
          type = "coreclr",
          name = "Program",
          request = "launch",
          env = function()
            local dll = ensure_dll()
            local vars = dotnet.get_environment_variables(dll.project_name, dll.relative_project_path)
            return vars or nil
          end,
          program = function()
            local dll = ensure_dll()
            local co = coroutine.running()
            rebuild_project(co, dll.project_path)
            return dll.relative_dll_path
          end,
          cwd = function()
            local dll = ensure_dll()
            return dll.relative_project_path
          end
        },
        {
          type = "coreclr",
          name = "Test",
          request = "attach",
          processId = function()
            local res = require("easy-dotnet").experimental.start_debugging_test_project()
            return res.process_id
          end
        }
      }
    end

    -- Reset debug_dll after each terminated session
    dap.listeners.before['event_terminated']['easy-dotnet'] = function()
      debug_dll = nil
    end

    dap.adapters.coreclr = {
      type = "executable",
      command = "netcoredbg",
      args = { "--interpreter=vscode" },
    }
    end
}
```


## Variables viewer

Debugging in statically typed languages like C# often involves navigating deeply nested runtime types such as `List<T>`, `Dictionary<K,V>`, or `HashSet<T>`. While tools like [`nvim-dap-ui`](https://github.com/rcarriga/nvim-dap-ui) provide a fantastic general-purpose interface for any language, they can’t always interpret the internal structure of .NET collections in a way that's intuitive to the user.

This plugin includes a custom variables viewer tailored specifically for the .NET ecosystem. It **automatically unwraps common C# types**, displaying concise, human-readable summaries of your data structures during debugging—no need to drill into private fields like `_items`, `_size`, or internal buckets.

This dramatically improves the debugging experience for C# and F# developers using Neovim.

## 📦 Supported Types

Out of the box, the following .NET types are recognized and automatically prettified:

* `System.Collections.ObjectModel.ReadOnlyCollection`
* `System.Collections.Generic.List`
* `System.Collections.Generic.SortedList`
* `System.Collections.Immutable.ImmutableList`
* `System.Collections.Concurrent.ConcurrentDictionary`
* `System.Collections.Generic.Dictionary`
* `System.Collections.Generic.OrderedDictionary`
* `System.Collections.ObjectModel.ReadOnlyDictionary`
* `System.Collections.Generic.HashSet`
* `System.Collections.Generic.Queue`
* `System.Collections.Generic.Stack`
* `System.DateOnly`
* `System.DateTime`
* `System.DateTimeOffset`
* `System.TimeOnly`
* `System.TimeSpan`
* `System.Enum`
* `System.Version`
* `System.Exception`
* `System.Guid`
* `System.Tuple<>`
* `System.Text.Json.JsonElement`
* `System.Text.Json.Nodes.JsonArray`
* `System.Text.Json.Nodes.JsonObject`
* `Newtonsoft.Json.Linq.JArray`
* `Newtonsoft.Json.Linq.JObject`
* `Newtonsoft.Json.Linq.JProperty`
* `Newtonsoft.Json.Linq.JValue`

## 🛠 How to Enable

Simply call this function during your DAP setup:

```lua
require("easy-dotnet.netcoredbg").register_dap_variables_viewer()
```

## Any missing types

If you encounter a type that isn’t yet handled, feel free to [open an issue](https://github.com/GustavEikaas/easy-dotnet.nvim/issues). Community contributions are always welcome!

## Virtual text 
Easy preview of variables while debugging, unwraps complex types
![image](https://github.com/user-attachments/assets/b6d53325-6527-43fd-bdb1-332dc8439197)

## Variable explorer
Let's you view and expand more complex variables. With automatic unwrapping
![image](https://github.com/user-attachments/assets/4e4c2cff-687b-4715-b5a8-b7ca67f7955b)


## Debugging with launch-profiles

The default profile being chosen must be named the same as your project.
The file is expected to be in the Properties/launchsettings.json relative to your .csproject file
If you want to be prompted to select a profile, remember to pass false as the last flag to `get_environment_variables`
```json
{
  "profiles": {
    "NeovimDebugProject.Api": {
      "commandName": "Project",
      "dotnetRunMessages": true,
      "launchBrowser": true,
      "launchUrl": "swagger",
      "environmentVariables": {
        "ASPNETCORE_ENVIRONMENT": "Development"
      },
      "applicationUrl": "https://localhost:7073;http://localhost:7071"
    }
}
```
