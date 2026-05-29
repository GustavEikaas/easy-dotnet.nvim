# Roslyn LSP integration

`easy-dotnet.nvim` provides **first-class Roslyn LSP integration** for Neovim out of the box.
It uses the same [LSP](https://github.com/dotnet/roslyn) implementation that powers **Visual Studio** and **VS Code**.

The **easy-dotnet Roslyn LSP** is enabled by default and requires **Neovim 0.11+**.
It uses the official `roslyn-language-server` .NET global tool. If the tool is missing, easy-dotnet installs it automatically with:

```bash
dotnet tool install --global roslyn-language-server --prerelease
```

Existing installs are not updated automatically. easy-dotnet periodically suggests updates, and you can update manually with:

```bash
dotnet-easydotnet roslyn update
```

## Razor and CSHTML

`*.razor` and `*.cshtml` files are handled by Roslyn LSP and are enabled by default.
easy-dotnet also bridges markup-backed Razor requests to VS Code's HTML language server so features such as HTML completion, hover, formatting, document symbols, and color support can work inside Razor files.

The HTML language server is an optional Node dependency. easy-dotnet does not bundle it and will not install it automatically.
If the dependency is missing, Razor still opens through Roslyn, but markup-backed requests return empty responses and `:checkhealth easy-dotnet` reports the missing command with install guidance.

Install the dependency globally:

```bash
npm install -g vscode-langservers-extracted
```

Or install it per project:

```bash
npm install --save-dev vscode-langservers-extracted
```

When `vscode-html-language-server` is available in project `node_modules/.bin` or on `PATH`, easy-dotnet starts it automatically for Razor files. No plugin configuration is required.

Override the command only if your install uses a custom location:

```lua
require("easy-dotnet").setup({
  lsp = {
    razor = {
      html = {
        cmd = { "vscode-html-language-server", "--stdio" },
      },
    },
  },
})
```

To disable Razor support:

```lua
require("easy-dotnet").setup({
  lsp = {
    razor = {
      enabled = false,
    },
  },
})
```

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
```


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

## CodeLens & Peek References

See reference counts
![image](https://github.com/user-attachments/assets/93bb557c-c97a-44a0-a51b-229cb65bddab)

### 1. Configure the Keymap
CodeLens actions (like "Go to References") are triggered via vim.lsp.codelens.run(). You can map this to a key for quick access:

```lua
-- Example: Trigger CodeLens action under cursor
vim.keymap.set("n", "<leader>cl", vim.lsp.codelens.run, { desc = "Run CodeLens" })
```
### 2. VS Code Visuals (Tip)
To make your CodeLens look more subtle and professional (like VS Code), add this highlight to your configuration:

```lua
-- Add this to your init.lua or colorscheme config
vim.api.nvim_set_hl(0, "LspCodeLens", { fg = "#717171", italic = true })
```

### 3. Peek Preview UI
When you run a "Find References" CodeLens action, easy-dotnet provides a custom floating UI.

![image](https://github.com/user-attachments/assets/165ab152-7afe-436b-9717-eacdbe63a690)

## Solution & Project Detection (How Roslyn LSP Decides What to Load)

`easy-dotnet.nvim` automatically discovers which **project** or **solution** your current file belongs to.
This determines how Roslyn behaves — what files it indexes, whether “go to definition” works across projects, and how rich your IntelliSense is.

When you open a `*.cs` file:

```
1. Roslyn LSP starts.
2. easy-dotnet looks for a .csproj or .sln file.
3. The first match determines the "target" for Roslyn:
     - If a .sln is found → Roslyn loads the whole solution
     - Else if a .csproj is found → Roslyn loads the project only
     - Else → Roslyn runs in "single-file mode"
```

Search order:

`directory of current file → parent → parent → ... → stop at Neovim’s cwd`

It **does not search downward** into sibling folders.

This is why the placement of your solution file matters.

---

## 🧭 Visual Overview

Here is the search behavior represented visually:

```
<CWD>  ← your Neovim working directory (search stops here)
│
├── src/
    ├── MySolution.sln
    │
    ├── App/
    │   ├── App.csproj    ← Not considered at all
    │   └── Program.cs
    │
    └── Library/
        ├── Library.csproj    ← Found but .sln has higher precedence
        └── Models/
            └── Customer.cs   ← current file (you opened this)

```


### ✔  Solution found

```
repo/
├── App.sln
└── src/
    └── Foo/Bar.cs
```

Opening Bar.cs → solution is found → cross-project navigation works.

---

### ❌ Solution not found

```
<CWD>  ← your Neovim working directory (search stops here)
│
├── src/
    │
    ├── App/
    │   ├── App.csproj    ← Not considered at all
    │   └── Program.cs
    │   └── MySln.cs      ← Sln is not in a parent directory of current file
    │
    └── Library/
        ├── Library.csproj    ← Found
        └── Models/
            └── Customer.cs   ← current file (you opened this)
```

Go to definition for symbols pointing to App will jump to decompiled code

---

### Workarounds

* Open Neovim **inside the folder containing the solution**
  `cd repo-root/Source && nvim`
* Or move/copy the `.sln` one folder up

---

### **1. Solution Mode**

Triggered when a `.sln` file is found.

Roslyn loads:

- ✔ whole solution
- ✔ all projects
- ✔ references between them
- ✔ best navigation & diagnostics

---

### **2. Project Mode**

Triggered when no solution is found, but a `.csproj` is.

Roslyn loads:

- ✔ only the project containing the file
- ✔ no cross-project navigation

---

### **3. Single-File Mode**

Triggered when neither `.sln` nor `.csproj` is found.

Roslyn behaves like:

- ⚠️ limited IntelliSense
- ⚠️ decompiled definitions
- ⚠️ no project context


## Commands
- `:Dotnet lsp start`
- `:Dotnet lsp stop`
- `:Dotnet lsp restart`
