---@meta
-- Type annotations for Roslyn workspace/configuration settings.
-- Source of truth: DidChangeConfigurationNotificationHandler_OptionList.cs in dotnet/roslyn.
-- Per-language options are requested as `csharp|<group>.<option>`, global options as `<group>.<option>`.
-- Enum values are parsed case-insensitively.

---@class easy-dotnet.Roslyn.Config : vim.lsp.Config
---@field settings? easy-dotnet.Roslyn.Settings

---@class easy-dotnet.Roslyn.Settings
---@field projects? easy-dotnet.Roslyn.Settings.Projects
---@field navigation? easy-dotnet.Roslyn.Settings.Navigation
---@field code_style? easy-dotnet.Roslyn.Settings.CodeStyle
---@field ["csharp|symbol_search"]? easy-dotnet.Roslyn.Settings.SymbolSearch
---@field ["csharp|type_members"]? easy-dotnet.Roslyn.Settings.TypeMembers
---@field ["csharp|completion"]? easy-dotnet.Roslyn.Settings.Completion
---@field ["csharp|quick_info"]? easy-dotnet.Roslyn.Settings.QuickInfo
---@field ["csharp|highlighting"]? easy-dotnet.Roslyn.Settings.Highlighting
---@field ["csharp|inlay_hints"]? easy-dotnet.Roslyn.Settings.InlayHints
---@field ["csharp|code_style"]? easy-dotnet.Roslyn.Settings.CSharpCodeStyle
---@field ["csharp|background_analysis"]? easy-dotnet.Roslyn.Settings.BackgroundAnalysis
---@field ["csharp|code_lens"]? easy-dotnet.Roslyn.Settings.CodeLens
---@field ["csharp|testing"]? easy-dotnet.Roslyn.Settings.Testing
---@field ["csharp|auto_insert"]? easy-dotnet.Roslyn.Settings.AutoInsert
---@field ["csharp|formatting"]? easy-dotnet.Roslyn.Settings.Formatting
---@field razor? easy-dotnet.Roslyn.Settings.Razor

---@class easy-dotnet.Roslyn.Settings.Projects
---@field dotnet_binary_log_path? string Directory to write MSBuild binary logs to while loading projects
---@field dotnet_enable_automatic_restore? boolean Default: true
---@field dotnet_load_on_demand? boolean Default: true
---@field dotnet_enable_file_based_programs? boolean Default: true
---@field dotnet_enable_file_based_programs_when_ambiguous? boolean Default: true

---@class easy-dotnet.Roslyn.Settings.Navigation
---@field dotnet_navigate_to_decompiled_sources? boolean Default: true
---@field dotnet_navigate_to_source_link_and_embedded_sources? boolean Default: true

---@class easy-dotnet.Roslyn.Settings.CodeStyle
---@field formatting? { new_line?: { insert_final_newline?: boolean } }

---@class easy-dotnet.Roslyn.Settings.SymbolSearch
---@field dotnet_search_reference_assemblies? boolean

---@class easy-dotnet.Roslyn.Settings.TypeMembers
---@field dotnet_member_insertion_location? "with_other_members_of_the_same_kind"|"at_the_end"
---@field dotnet_property_generation_behavior? "prefer_throwing_properties"|"prefer_auto_properties"

---@class easy-dotnet.Roslyn.Settings.Completion
---@field dotnet_show_name_completion_suggestions? boolean
---@field dotnet_provide_regex_completions? boolean
---@field dotnet_show_completion_items_from_unimported_namespaces? boolean
---@field dotnet_completion_items_from_unimported_namespaces_commit_behavior? "alwaysAddImport"|"neverAddImport"|"onlyAddImportIfExplicitlyCompleted"
---@field dotnet_trigger_completion_in_argument_lists? boolean

---@class easy-dotnet.Roslyn.Settings.QuickInfo
---@field dotnet_show_remarks_in_quick_info? boolean

---@class easy-dotnet.Roslyn.Settings.Highlighting
---@field dotnet_highlight_related_json_components? boolean
---@field dotnet_highlight_related_regex_components? boolean

---@class easy-dotnet.Roslyn.Settings.InlayHints
---@field dotnet_enable_inlay_hints_for_parameters? boolean
---@field dotnet_enable_inlay_hints_for_literal_parameters? boolean
---@field dotnet_enable_inlay_hints_for_indexer_parameters? boolean
---@field dotnet_enable_inlay_hints_for_object_creation_parameters? boolean
---@field dotnet_enable_inlay_hints_for_other_parameters? boolean
---@field dotnet_suppress_inlay_hints_for_parameters_that_differ_only_by_suffix? boolean
---@field dotnet_suppress_inlay_hints_for_parameters_that_match_method_intent? boolean
---@field dotnet_suppress_inlay_hints_for_parameters_that_match_argument_name? boolean
---@field csharp_enable_inlay_hints_for_types? boolean
---@field csharp_enable_inlay_hints_for_implicit_variable_types? boolean
---@field csharp_enable_inlay_hints_for_lambda_parameter_types? boolean
---@field csharp_enable_inlay_hints_for_implicit_object_creation? boolean
---@field csharp_enable_inlay_hints_for_collection_expressions? boolean

---@class easy-dotnet.Roslyn.Settings.CSharpCodeStyle
---@field formatting? easy-dotnet.Roslyn.Settings.CSharpCodeStyle.Formatting

---@class easy-dotnet.Roslyn.Settings.CSharpCodeStyle.Formatting
---@field indentation_and_spacing? { tab_width?: integer, indent_size?: integer, indent_style?: "space"|"tab" }
---@field new_line? { end_of_line?: "lf"|"cr"|"crlf" }

---@class easy-dotnet.Roslyn.Settings.BackgroundAnalysis
---@field dotnet_analyzer_diagnostics_scope? easy-dotnet.Roslyn.DiagnosticsScope
---@field dotnet_compiler_diagnostics_scope? easy-dotnet.Roslyn.DiagnosticsScope Default: "openFiles"

---@alias easy-dotnet.Roslyn.DiagnosticsScope "openFiles"|"fullSolution"|"none"|"visibleFilesAndOpenFilesWithPreviouslyReportedDiagnostics"

---@class easy-dotnet.Roslyn.Settings.CodeLens
---@field dotnet_enable_references_code_lens? boolean Default: true
---@field dotnet_enable_tests_code_lens? boolean Default (easy-dotnet): false

---@class easy-dotnet.Roslyn.Settings.Testing
---@field dotnet_use_semantic_test_discovery? boolean Default: false

---@class easy-dotnet.Roslyn.Settings.AutoInsert
---@field dotnet_enable_auto_insert? boolean Default: true

---@class easy-dotnet.Roslyn.Settings.Formatting
---@field dotnet_organize_imports_on_format? boolean Default: false

---@class easy-dotnet.Roslyn.Settings.Razor
---@field language_server? { cohosting_enabled?: boolean }
