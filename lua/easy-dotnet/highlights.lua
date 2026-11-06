local constants = require("easy-dotnet.constants")

local M = {}

function M.define()
  --TODO: stop polluting global namespace
  vim.api.nvim_set_hl(0, "EasyDotnetPackage", {
    fg = "#000000",
    bg = "#ffffff",
    bold = true,
    italic = false,
    underline = false,
  })

  --Testrunner
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerSolution, { link = "Question" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerProject, { link = "Character" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerTest, { link = "Normal" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerSubcase, { link = "Conceal" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerDir, { link = "Directory" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerPackage, { link = "Include" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerPassed, { link = "DiagnosticOk" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerFailed, { link = "DiagnosticError" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerInconclusive, { link = "DiagnosticHint" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerRunning, { link = "DiagnosticWarn" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerQueued, { link = "Comment" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetTestRunnerProbable, { link = "Comment" })
  --Roslyn semantic tokens
  -- `excludedCode` is an off-spec token type Roslyn sends for code inside inactive
  -- preprocessor branches (`#if DEBUG` when building Release). Neovim only pre-links the
  -- standard LSP token types, so without this the block renders as if it were active.
  -- `default = true` so colorschemes and user config can override it.
  vim.api.nvim_set_hl(0, "@lsp.type.excludedCode", { link = "Comment", default = true })

  local razor_highlights = {
    markupAttributeQuote = "@string",
    markupAttribute = "@tag.attribute",
    markupAttributeValue = "@string",
    markupCommentPunctuation = "@comment",
    markupComment = "@comment",
    markupElement = "@tag",
    markupOperator = "@operator",
    markupTagDelimiter = "@tag.delimiter",
    markupTextLiteral = "@none",
    razorCommentStar = "@comment",
    razorCommentTransition = "@comment",
    razorComment = "@comment",
    razorComponentAttribute = "@property",
    razorComponentElement = "@type",
    razorDirectiveAttribute = "@attribute",
    razorDirectiveColon = "@punctuation.delimiter",
    razorDirective = "@keyword",
    razorTagHelperAttribute = "@tag.attribute",
    razorTagHelperElement = "@type",
    razorTransition = "@punctuation.special",
  }
  for token, link in pairs(razor_highlights) do
    vim.api.nvim_set_hl(0, "@lsp.type." .. token .. ".razor", { link = link, default = true })
  end

  --Debugger
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetDebuggerFloatVariable, { link = "Question" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetDebuggerVirtualVariable, { link = "Question" })
  vim.api.nvim_set_hl(0, constants.highlights.EasyDotnetDebuggerVirtualException, { link = "DiagnosticError" })

  local bg_color = "#1e1e1e"
  local active_bg = "#252526"
  local accent = "#007acc"

  local peek_hls = {
    [constants.highlights.EasyDotnetPeekWinBar] = { bg = bg_color, fg = "#ffffff", bold = true },
    [constants.highlights.EasyDotnetPeekSideBar] = { bg = bg_color, fg = "#cccccc" },
    [constants.highlights.EasyDotnetPeekMain] = { bg = active_bg },
    [constants.highlights.EasyDotnetPeekBorder] = { fg = accent, bg = "NONE" },
    [constants.highlights.EasyDotnetPeekTitle] = { fg = "#ffffff", bg = accent, bold = true },
    [constants.highlights.EasyDotnetPeekHint] = { fg = "#858585", bg = bg_color, italic = true },
    [constants.highlights.EasyDotnetPeekListActive] = { bg = "#094771", fg = "#ffffff" },
  }

  for group, opts in pairs(peek_hls) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

return M
