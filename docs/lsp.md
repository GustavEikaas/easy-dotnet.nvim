# Roslyn LSP integration

`easy-dotnet.nvim` provides **first-class Roslyn LSP integration** for Neovim out of the box.  
It uses the same [LSP](https://github.com/dotnet/roslyn) implementation that powers **Visual Studio** and **VS Code**.

The **easy-dotnet Roslyn LSP** is enabled by default and requires **Neovim 0.11+**.


## Analyzers

- **Roslynator** is enabled by default.
- The language server bundles both the **Roslyn LSP** and **Roslynator analyzers**.
- You can add **additional analyzer assemblies** by passing them in your setup:

```lua
require("easy-dotnet").setup({
    lsp = {
        analyzer_assemblies = {
            "usr/local/share/SonarAnalyzer.CSharp.dll",
        },
    },
})
````


## LSP Settings

To customize LSP settings, it’s recommended to use this neovim 0.11+ pattern:

```
~\AppData\Local\nvim
├── .git
├── lsp
│   └── easy_dotnet.lua      <-- LSP settings go in this file
└── lua
    └── init.lua
```

Example `lsp/easy_dotnet.lua` configuration:

```lua
---@type vim.lsp.Config
return {
  settings = {
    ["csharp|inlay_hints"] = {
      csharp_enable_inlay_hints_for_implicit_object_creation = true,
      csharp_enable_inlay_hints_for_implicit_variable_types = true,
    },
    ["csharp|code_lens"] = {
      dotnet_enable_references_code_lens = true,
    },
    ["csharp|formatting"] = {
      dotnet_organize_imports_on_format = true,
    },
  },
}
```

## Commands
- `:Dotnet lsp start`
- `:Dotnet lsp stop`
- `:Dotnet lsp restart`

## Known Issues

These are current known limitations and flaws in the Roslyn integration:

### ⚠️ New Files Not Added to Project

Newly created `.cs` files are **not automatically added to a project**.
Because of this, the LSP treats them as **standalone files**, resulting in:

* Limited completions
* Missing project-level diagnostics
* No project-wide references
* link gh issue here

To work around this, run:
```
:Dotnet lsp restart
```


