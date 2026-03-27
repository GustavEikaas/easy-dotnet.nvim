# News

This document is intended for documenting major improvements to this plugin. It can be a good idea to check this document occasionally

## Workspace run and debug moved to the server ([#858](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/858))

`:Dotnet run` and `:Dotnet debug` have now been moved fully into the C# server, similar to the test runner rewrite.
This also improves support for running and debugging file-based apps. Debugging file-based apps was not possible at all previously.
It now uses the newer managed terminal flow instead of the older user-provided `options.terminal` path.
CLI arg passthrough when debugging has also been improved, so `:Dotnet debug --abc` will pass `--abc` to the debuggee.

### What this means for you

Run and debug should now behave more consistently, and the server has much better heuristics for deciding whether something should be treated as a project or as a file-based app.

If you want debugging in a separate window, you can use the `external_terminal` option.

```lua 
dotnet.setup({
    -- Some examples
    -- local windows_term = { command = "wt", args = { "-w", "-1", "nt", "--" } }
    -- local linux_term = { command = "kitty", args = { "--hold", "--" } }
    external_terminal = nil,
})

## Test Runner v2 ([#838](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/838))

The test runner has been completely rewritten. The old implementation was almost entirely Lua, which made it very hard to refactor or improve without introducing regressions. Moving it to the C# server (as discussed in [#809](https://github.com/GustavEikaas/easy-dotnet.nvim/issues/809)) brings strong typing, proper testability, and a much cleaner boundary between UI and business logic. The Lua side is now a thin UI layer the server handles everything else.

If you run into regressions, please report them in the dedicated feedback issue [#841](https://github.com/GustavEikaas/easy-dotnet.nvim/issues/841) the test runner is complex and edge cases are expected.

### What's new

**Auto-start and silent background discovery**

The test runner now starts automatically when the server starts. Discovery runs silently in the background against any already-built DLLs, so the tree is populated before you even open the window. For projects that haven't been built yet, the runner waits until you open the window and then builds and discovers the remaining projects automatically. No more cold-start friction.

This can be disabled if you prefer to start the runner manually:

```lua
dotnet.setup({
  test_runner = {
    auto_start_testrunner = false,
  }
})
```

**Cancellation support**

There was previously no cancellation support closing the window or triggering a new run had no effect on whatever the test binary was doing. The runner now supports cancellation properly, signalling the test binary to stop and waiting for it to finish cleanly.

**Class-level test execution from buffer**

You can now run an entire test class directly from the buffer. This replaces the old `run_all_tests_from_buffer` command, which only ran individual methods.

**Improved debugger integration**

Debugging can now be triggered from namespace, class, and project nodes in the runner, not only from individual tests or theory groups.

Automatic breakpoint insertion when starting a debug session from the runner or buffer has been removed. Breakpoints need to be set manually. With debug now supported at the namespace, class, and project level there is no single sensible location to insert a breakpoint automatically, so breakpoints are left entirely to you.

**Flash on run and completion from buffer**

When you trigger a test from the buffer, the method or class flashes to confirm the run was picked up. When the run finishes, it flashes again in the colour of the result green for passed, red for failed, and so on. Both methods and classes support this.

**Improved floating stacktrace from buffer**

The floating stacktrace view now focuses on the stacktrace itself. The source buffer float is hidden in this mode as it provides no useful information.

The stacktrace is now parsed and syntax highlighted. Lines from your own code are highlighted in yellow and framework code is dimmed in grey, making it easy to see at a glance where in your code the failure originated. Press `<CR>` on any yellow line to jump directly to that location.

**Class-level icons and signs**

Test result icons and gutter signs are now tracked at the class level in addition to individual methods.

**Correct and responsive test signs**

Previously, signs were placed based on line positions reported by the DLL at build time. This meant signs would render on incorrect lines whenever you edited a file and would stay wrong until the next rebuild. Under heavy editing this could also produce out-of-bounds errors as the runner tried to place signs on lines that no longer existed.

Signs now use the Roslyn AST to sync their position after every `BufWritePost`, so they always reflect the current state of the file regardless of edits.

Because we now resolve test locations through Roslyn rather than relying on what the test adapters report, a few other things also improved. We now know the start line of the method body and the end line of each test method, neither of which are reported by VSTest or MTP. We also use a consistent line for both adapters: previously MTP pointed to the [Test] attribute line and VSTest pointed to the function signature line, making them disagree on the same test. Both now resolve to the same location.

**Stable tree during rediscovery**

The tree no longer collapses while rediscovery is running. Only new and orphaned nodes are affected newly discovered nodes are added and nodes that no longer exist are removed, while everything else stays exactly where it was.

**`M.get_test_results` removed**

This API was added in [#485](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/485) to support use cases like displaying test results as code lens via plugins such as [lensline.nvim](https://github.com/oribarilan/lensline.nvim). It has been removed in v2 and test signs are the intended replacement for surfacing results outside the runner window. If signs don't cover your use case please open an issue and we can figure out the best way to bring that functionality back properly.

### Breaking changes

**Removed options**

- `noBuild` no longer meaningful given how the runner manages the build lifecycle
- `enable_buffer_test_execution` buffer test execution is always enabled now. If you want to disable it, simply unbind the default keys
- `additional_args` removed. Passing global additional args independent of project context doesn't really make sense use a `.runsettings` file or the MTP equivalent instead
- `run_all_tests_from_buffer` keybind removed. Now that running an entire class from the buffer is supported, this command no longer makes sense

Remove these from your config.

### Performance improvements

- Silent background discovery on startup means the tree is populated before you open it
- Now using the new `EasyDotnet.BuildServer` which is significantly faster than the old dotnet CLI wrapper, and also improves test project properties resolution
- Multi-project runs share a single build step
- Incremental tree diffing only changed nodes trigger a re-render

### UI/UX improvements

- The runner now has a proper header and footer window. Previously there was only virtual text that would disappear if you scrolled too far down
- The header right-aligns pass/fail/skip counts and degrades gracefully in narrow splits
- Spinner and status update live during runs without re-rendering the full tree
- Improved layout responsiveness the runner handles resizing correctly in all split modes

### Upgrade notes

1. Remove `noBuild`, `enable_buffer_test_execution`, `additional_args`, and any `run_all_tests_from_buffer` bindings from your config
2. Migrate any extra test arguments to `.runsettings` or MTP config

If something that worked in v1 is broken, please drop a note in [#841](https://github.com/GustavEikaas/easy-dotnet.nvim/issues/841)

## Interactive debugger console ([#813](https://github.com/GustavEikaas/easy-dotnet.nvim/pull/813))

As many of you know, `easy-dotnet` automatically configures DAP for you with netcoredbg, some of you probably noticed that `Console.ReadLine()` would throw an exception due to netcoredbg not running in an actual console. To make matters worse, all of your application's output was dumped directly into the DAP REPL, creating a messy debugging experience.

This is now fixed in the latest release! We completely overhauled how the debugger handles process execution, bringing the Neovim debugging experience much closer to Visual Studio.

### What this means for you

* **Full Interactivity:** You can now type input directly into your running C# application! CLI tools and interactive prompts work flawlessly.
* **A Clean REPL:** Your application's standard output is now properly routed to the console widget (or an external terminal). Your REPL is finally clean!
* **Native External Terminals:** Want your app to pop open in a dedicated, detached OS window (like Windows Terminal or Kitty) just like hitting F5 in Visual Studio? The `externalTerminal` option is now supported!

### Configuration

The `integratedTerminal` option is used by default. You can configure this preference in your options. 

If you choose to use an `externalTerminal`, you will need to tell `nvim-dap` which terminal emulator to use on your machine:

```lua
local dotnet = require("easy-dotnet")

dotnet.setup({
  debugger = {
    console = "externalTerminal", 
  }
})

-- Instructions on how dap creates an external terminal window:
local dap = require("dap")

-- Windows (Windows Terminal)
dap.defaults.fallback.external_terminal = {
  command = "wt",
  args = { "-w", "0", "nt", "--" },
}

-- Linux (Kitty)
dap.defaults.fallback.external_terminal = {
  command = "/usr/bin/kitty",
  args = { "--hold" } 
}
```

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

