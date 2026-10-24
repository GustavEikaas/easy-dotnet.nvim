local M = {
  buildType = nil,
  displayName = nil,
}

function M.set(state)
  M.buildType = state and state.buildType or nil
  M.displayName = state and state.displayName or nil
end

function M.get()
  return {
    buildType = M.buildType,
    displayName = M.displayName,
  }
end

---@return string
function M.msbuild_configuration() return M.buildType or "Debug" end

function M.apply_to_lsp()
  local lsp_opts = require("easy-dotnet.options").get_option("lsp")
  if not (lsp_opts and lsp_opts.enabled) then return end
  require("easy-dotnet.roslyn.lsp").apply_configuration(M.msbuild_configuration())
end

function M.lualine() return M.displayName or "" end

return M
