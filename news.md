# News

This document is intended for documenting major improvements to this plugin. It can be a good idea to check this document occasionally

## Preloading Roslyn ([#794](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/794))

Neovim traditionally waits to start LSP servers until you open a buffer of the relevant filetype. This creates a noticeable delay when opening your first C# file.

With this feature, `easy-dotnet` starts loading Roslyn immediately when your plugin setup is called, rather than waiting for you to navigate to a file. This background loading ensures the server is often "warm" and ready by the time you start typing, making the IDE experience significantly smoother.

### How it works

The LSP will preload automatically if:

* The `preload_roslyn` option is enabled (it is `true` by default).
* A solution file is successfully selected or detected during startup.

### Configuration

This feature is enabled by default, but you can configure it specifically in your `lsp` table:

```lua
dotnet.setup({
  lsp = {
    enabled = true, -- Enable builtin roslyn lsp
    preload_roslyn = true, -- Start loading roslyn before any buffer is opened
  },
})
```

## Automatic .NET Variable Conversion ([#666](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/666))

Debugging in C# and F# just got significantly more readable. With this release, **common .NET types are automatically unwrapped and displayed in a concise, human-friendly format** across any DAP-compliant UI in Neovim, including `nvim-dap-ui`, `nvim-dap-view`, and others.

Previously, inspecting variables often required navigating internal fields such as `_items`, `_size`, or thread-local queues. Now, with **value converters enabled by default**, variables like `List<T>`, `Dictionary<K,V>`, and `CancellationTokenSource` are displayed cleanly without drilling into private fields.

### What this means for you

* **Immediate readability:** See the contents of collections and other common types directly.
* **DAP-compliant:** Works with any DAP UI plugin — no custom UI required.
* **Optional:** Can be disabled globally by setting:

```lua
require("easy-dotnet").setup({    
  debugger = {
    apply_value_converters = false,
  }
})
```


### Example: `List<string>`

**Converted (new):**

```
x System.Collections.Generic.List<string> = {System.Collections.Generic.List<string>}
  [0] string = "hello"
  [1] string = "world"
```

**Previous view (old):**

```
x System.Collections.Generic.List<string> = {System.Collections.Generic.List<string>}
  _items string[] = {string[4]}
    [0] string = "hello"
    [1] string = "world"
    [2] string = null
    [3] string = null
  _size int = 2
  _version int = 2
  Capacity int = 4
  Count int = 2
  System.Collections.IList.IsFixedSize bool = false
  System.Collections.Generic.ICollection<T>.IsReadOnly bool = false
  System.Collections.IList.IsReadOnly bool = false
  System.Collections.ICollection.IsSynchronized bool = false
  System.Collections.ICollection.SyncRoot System.Collections.Generic.List<string> = {…}
  Item System.Reflection.TargetParameterCountException = {…}
  System.Collections.IList.Item System.Reflection.TargetParameterCountException = {…}
  Static members
```

## Supported Types

The converters currently handle most basic types, lists, hashsets, queues, read-only collections, time types, and threading primitives like `CancellationToken`.

If you encounter a type that isn’t yet handled, or want a specific value converter, please file an issue

Community contributions are always welcome.


## Bundled NetCoreDbg - Zero Installation Debugging ([#204](https://github.com/GustavEikaas/easy-dotnet-server/pull/204))

Debugging just got even easier.  NetCoreDbg is now bundled directly with easy-dotnet-server for all platforms. 

Previously, users had to manually install NetCoreDbg (typically via Mason) and configure the `bin_path` option to point to the debugger executable. This added unnecessary friction to the setup process and could lead to version mismatches or platform-specific issues.

With this release, easy-dotnet-server automatically includes NetCoreDbg binaries for Linux (x64/ARM64), macOS (x64), and Windows (x64). The plugin intelligently selects the correct binary for your platform at runtime.

### What this means for you

- **No manual installation**: NetCoreDbg comes bundled — just install easy-dotnet-server and start debugging
- **No bin_path configuration**: The `debugger.bin_path` option is now completely optional
- **Always compatible**: NetCoreDbg version is guaranteed to work with your server version
- **Automatic updates**: When you run `dotnet tool update -g EasyDotnet`, you get the latest debugger too
- **Cross-platform by default**: Works seamlessly on Linux, macOS, and Windows without platform-specific setup

### Migration guide

If you previously configured NetCoreDbg manually, you can now simplify your setup:

**Before:**
```lua
dotnet.setup {
  debugger = {
    bin_path = vim.fn.stdpath("data") .. "/mason/bin/netcoredbg", -- Required
    auto_register_dap = true,
  }
}
```

**After:**
```lua
dotnet.setup {
  debugger = {
    -- bin_path is now optional - falls back to bundled NetCoreDbg
    auto_register_dap = true,
  }
}
```
**Note**: If you still prefer to use your own NetCoreDbg installation (e.g., via Mason) or another CoreCLR DAP adapter, the `bin_path` option continues to work as before.

### Technical details

The bundled NetCoreDbg is extracted from official [Samsung/netcoredbg](https://github.com/Samsung/netcoredbg) releases during the CI build process and packaged with the . NET tool. At runtime, easy-dotnet-server automatically detects your platform and uses the appropriate binary.

This approach ensures you always have a working, tested debugger without any manual intervention. 

## Roslyn native lsp setup
Read more [here](./docs/lsp.md) or in the PR #632

### Pros 

- Uses the new vim.lsp.config api
- Easier
- :LspRestart works now
- More maintainable
- More extendable for end users
- Users can register lsp config in `./lsp/easy_dotnet.lua`


## Roslyn LSP 0 click setup ([#539](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/539))
This release marks a major milestone for easy-dotnet.nvim.
With this update, Roslyn is now installed and configured automatically. No manual setup required.

You no longer need separate plugins like roslyn.nvim or omnisharp-vim, as LSP support is built directly into easy-dotnet.
If you prefer to keep using an external LSP, simply disable the built-in one by setting:
```lua
options.lsp.enabled = false
```

Additionally, Roslynator is now installed and enabled by default, providing richer refactorings and deeper code analysis right out of the box.

### How can I start using this
It’s enabled by default. Just disable any existing C# LSPs you may have configured.

You can pass settings to roslyn like this
```lua
local dotnet = require "easy-dotnet"

dotnet.setup {
  lsp = {
    enabled = true,
    config = {
      settings = {
        ["csharp|background_analysis"] = {
          dotnet_compiler_diagnostics_scope = "fullSolution",
        },
        ["csharp|inlay_hints"] = {
          csharp_enable_inlay_hints_for_implicit_object_creation = true,
        },
        ["csharp|code_lens"] = {
          dotnet_enable_references_code_lens = true,
        },
      },
    },
  },
  ...
}
```

## NetCoreDbg 0 click DAP configuration ([#523](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/523))
Setting up debugging for .NET projects in Neovim has historically been tedious and error-prone. Involving manual project rebuilds, DLL resolution, and complex nvim-dap configurations.
This release completely changes that.

With easy-dotnet’s built-in NetCoreDbg integration, the plugin now handles all the heavy lifting for you.
By leveraging easy-dotnet-server, debugger setup, attach/launch, and breakpoint handling are all automated behind the scenes.

You no longer need to manually write DAP configurations for typical .NET workflows.

### Features

- Automatic DAP setup: No manual dap.configurations required.
- Smart project detection: Automatically attaches to the right context (console, VSTest, or MTP).
- Easy debugging workflow: Starts, attaches, and manages the NetCoreDbg process transparently.
- [easy-dotnet-server](https://github.com/GustavEikaas/easy-dotnet-server): Acts as a smart proxy between Neovim and NetCoreDbg, rewriting requests and responses as needed.
- Automatically normalize breakpoints (windows): Automatically fixes this issue [nvim-dap#1551](https://github.com/mfussenegger/nvim-dap/issues/1551)

### How can I start using this

1. Remove any existing DAP configuration for C#.
2. Set your debugger path:
```lua

local dotnet = require "easy-dotnet"

dotnet.setup {
  debugger = {
    -- or full path to netcoredbg executable. (can be installed with mason)
    bin_path = "netcoredbg",
  }
}
```

## .NET framework support ([#484](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/484))

This release brings native support for .NET Framework
You can now build, run, and test classic .NET Framework projects directly inside Neovim including full testrunner integration and support for IIS-based projects.
LSP functionality is also supported out of the box.

Debugger support is not yet available, as no open-source, DAP-compliant CLR debugger exists. However, all core workflows are now functional and ready for daily use.

### How can I start using this
- Visual Studio must be installed (required for MSBuild).
- Install the nuget CLI via Chocolatey or other sources
```sh
choco install nuget.commandline
```
- Set this option in your setup:
```lua
options.server.use_visual_studio = true
```

