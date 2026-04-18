local M = {}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client

---@param project_path string | nil
---@param allow_prerelease boolean | nil
M.search_nuget = function(project_path, allow_prerelease)
  allow_prerelease = allow_prerelease or false
  client:initialize(function()
    client.package_manager:add(project_path, allow_prerelease)
  end)
end

M.get_nuget_sources_async = function()
  local co = coroutine.running()
  client:initialize(function()
    client.nuget:nuget_list_sources(function(res)
      coroutine.resume(co, vim.tbl_map(function(value) return { name = value.name, display = value.name } end, res))
    end)
  end)
  return coroutine.yield()
end

---@param project_path string | nil
M.remove_nuget = function(project_path)
  client:initialize(function()
    client.package_manager:remove(project_path)
  end)
end

return M
