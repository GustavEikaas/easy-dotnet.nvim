# LSP in .NET

`easy-dotnet.nvim` provides **first-class Roslyn LSP integration** for Neovim out of the box.  
It uses the same LSP implementation that powers **Visual Studio** and **VS Code**, backed by the official Roslyn compiler:

👉 https://github.com/dotnet/roslyn

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
    },
}
```


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


## Commands
- `:Dotnet lsp start`
- `:Dotnet lsp stop`
- `:Dotnet lsp restart`




                "symbol_search.dotnet_search_reference_assemblies",
                "type_members.dotnet_member_insertion_location",
                "type_members.dotnet_property_generation_behavior",
                "completion.dotnet_show_name_completion_suggestions",
                "completion.dotnet_provide_regex_completions",
                "completion.dotnet_show_completion_items_from_unimported_namespaces",
                "completion.dotnet_trigger_completion_in_argument_lists",
                "quick_info.dotnet_show_remarks_in_quick_info",
                "navigation.dotnet_navigate_to_decompiled_sources",
                "highlighting.dotnet_highlight_related_json_components",
                "highlighting.dotnet_highlight_related_regex_components",
                "inlay_hints.dotnet_enable_inlay_hints_for_parameters",
                "inlay_hints.dotnet_enable_inlay_hints_for_literal_parameters",
                "inlay_hints.dotnet_enable_inlay_hints_for_indexer_parameters",
                "inlay_hints.dotnet_enable_inlay_hints_for_object_creation_parameters",
                "inlay_hints.dotnet_enable_inlay_hints_for_other_parameters",
                "inlay_hints.dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix",
                "inlay_hints.dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent",
                "inlay_hints.dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name",
                "inlay_hints.csharp_enable_inlay_hints_for_types",
                "inlay_hints.csharp_enable_inlay_hints_for_implicit_variable_types",
                "inlay_hints.csharp_enable_inlay_hints_for_lambda_parameter_types",
                "inlay_hints.csharp_enable_inlay_hints_for_implicit_object_creation",
                "inlay_hints.csharp_enable_inlay_hints_for_collection_expressions",
                "code_style.formatting.indentation_and_spacing.tab_width",
                "code_style.formatting.indentation_and_spacing.indent_size",
                "code_style.formatting.indentation_and_spacing.indent_style",
                "code_style.formatting.new_line.end_of_line",
                "code_style.formatting.new_line.insert_final_newline",
                "background_analysis.dotnet_analyzer_diagnostics_scope",
                "background_analysis.dotnet_compiler_diagnostics_scope",
                "code_lens.dotnet_enable_references_code_lens",
                "code_lens.dotnet_enable_tests_code_lens",
                "auto_insert.dotnet_enable_auto_insert",
                "projects.dotnet_binary_log_path",
                "projects.dotnet_enable_automatic_restore",
                "navigation.dotnet_navigate_to_source_link_and_embedded_sources",
                "formatting.dotnet_organize_imports_on_format",
