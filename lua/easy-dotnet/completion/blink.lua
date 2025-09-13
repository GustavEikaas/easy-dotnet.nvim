local polyfills = require("easy-dotnet.polyfills")

local M = {
  include_pending = nil,
  version_pending = nil,
}

function M.new() return setmetatable({}, { __index = M }) end

function M:get_trigger_characters() return { 'Include="', "Include='", "Version='", 'Version="' } end

function M:enabled()
  local filetypes = { "csproj", "fsproj", "xml" }
  local is_enabled = vim.tbl_contains(filetypes, vim.bo.filetype)
  return is_enabled
end

function M:get_completions(ctx, callback)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local transformed_callback = function(items)
    callback({
      context = ctx,
      is_incomplete_forward = true,
      is_incomplete_backward = true,
      items = items,
    })
  end

  local _, col = unpack(vim.api.nvim_win_get_cursor(0))
  local current_line = vim.api.nvim_get_current_line()
  local before_cursor = current_line:sub(1, col)
  local package_completion_pattern = 'Include="[^"]*$'
  local version_completion_pattern = 'Version="[^"]*$'
  local inside_include = before_cursor:match(package_completion_pattern)
  local inside_version = before_cursor:match(version_completion_pattern)

  if inside_include then
    local search_term = inside_include:gsub('%Include="', "")

    if M.include_pending then
      client._client.cancel(M.include_pending)
      M.include_pending = nil
    end
    client:initialize(function()
      M.include_pending = client.nuget:nuget_search(search_term, nil, function(res)
        local items = polyfills.tbl_map(function(value)
          local label = string.format("%s (%s)", value.id, value.source)
          return { label = label, dup = 0, insertText = value.id, documentation = "", kind = 11 }
        end, res)
        transformed_callback(items)
      end).id
    end)

    return
  elseif inside_version then
    if M.version_pending then
      client._client.cancel(M.version_pending)
      M.version_pending = nil
    end
    local package_name = current_line:match('Include="([^"]+)"')
    client:initialize(function()
      M.version_pending = client.nuget:nuget_get_package_versions(package_name, nil, false, function(res)
        local index = 0
        local latest = nil
        local last_index = #res - 1
        local items = polyfills.tbl_map(function(i)
          index = index + 1
          local cmp_item = {
            label = i,
            insertText = i,
            documentation = "",
            dup = 0,
            kind = 11,
          }
          if index == last_index then latest = cmp_item.label end
          return cmp_item
        end, res)
        if latest then
          table.insert(items, {
            label = "latest",
            insertText = latest,
            documentation = "Insert latest version available: " .. latest,
            kind = 15,
            preselect = true,
          })
        end
        transformed_callback(items)
      end).id
    end)
    return
  end

  transformed_callback({})

  return function() end
end

return M
