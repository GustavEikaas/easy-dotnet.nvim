-- ============================================================
-- TODO: REMOVE BEFORE MERGE — picker debug/testing helpers
-- ============================================================

local rpc = require("easy-dotnet.rpc.rpc-client")

local M = {}

local function invoke(method)
  rpc.request(method, {}, function(res)
    if res and res.error then
      vim.schedule(function() vim.notify("[test_picker] error: " .. vim.inspect(res.error), vim.log.levels.ERROR) end)
    end
  end)
end

function M.test_picker() invoke("_test/picker") end
function M.test_picker_preview() invoke("_test/picker-preview") end
function M.test_multi_picker_preview() invoke("_test/multi-picker-preview") end
function M.test_live_preview() invoke("_test/live-preview") end
function M.test_nuget_search() invoke("_test/nuget-search") end

return M
