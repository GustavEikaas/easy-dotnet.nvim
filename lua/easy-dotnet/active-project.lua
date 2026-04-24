local M = {
  projectPath = nil,
  projectName = nil,
  launchProfile = nil,
}

function M.set(state)
  M.projectPath = state and state.projectPath or nil
  M.projectName = state and state.projectName or nil
  M.launchProfile = state and state.launchProfile or nil
end

function M.get()
  return {
    projectPath = M.projectPath,
    projectName = M.projectName,
    launchProfile = M.launchProfile,
  }
end

function M.lualine()
  if not M.projectName then return "" end
  if M.launchProfile and M.launchProfile ~= M.projectName then return M.projectName .. " [" .. M.launchProfile .. "]" end
  return M.projectName
end

return M
