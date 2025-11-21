# News

This document is intended for documenting major improvements to this plugin. It can be a good idea to check this document occasionally

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

