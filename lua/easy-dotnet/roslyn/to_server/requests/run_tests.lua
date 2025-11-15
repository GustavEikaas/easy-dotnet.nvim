local lsp_helper = require("easy-dotnet.roslyn.create_lsp_call")

-- msg.progress may contain
--  {
--     testsFailed = 0,
--     testsPassed = 0,
--     testsSkipped = 0,
--     totalTests = 1
--   },
--

---@class RunTestsParams
---@field textDocument lsp.TextDocumentIdentifier
---@field range lsp.Range
---@field attachDebugger boolean
---@field runSettingsPath? string

---@class TestProgress
---@field testsPassed integer
---@field testsFailed integer
---@field testsSkipped integer
---@field totalTests integer

---@class RunTestsPartialResult
---@field stage string
---@field message string
---@field progress? TestProgress

local M = {}

---Run tests using Roslyn LSP with automatic spinner
---@param client vim.lsp.Client
---@param params RunTestsParams
---@param on_result fun( result:RunTestsPartialResult[]|nil)
---@param on_error fun(err)
---@return LSP_CallHandle
function M.run_tests(client, params, on_result, on_error)
  return lsp_helper.create_lsp_call({
    client = client,
    method = "textDocument/runTests",
    params = params,
    supports_progress = true,
    on_progress = function(msg) vim.print("[progress]: ", msg) end,
    on_result = on_result,
    on_error = on_error,
  })()
end

return M
