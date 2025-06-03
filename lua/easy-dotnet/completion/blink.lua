local polyfills = require("easy-dotnet.polyfills")
local cli = require("easy-dotnet.dotnet_cli")

local M = {}

function M.new() return setmetatable({}, { __index = M }) end

function M:get_trigger_characters() return { 'Include="', "Include='", "Version='", 'Version="' } end

function M:enabled()
  local filetypes = { "csproj", "fsproj", "xml" }
  local is_enabled = vim.tbl_contains(filetypes, vim.bo.filetype)
  return is_enabled
end

function M:get_completions(ctx, callback)
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
    local command = cli.package_search(search_term, true, false, 5)
    vim.fn.jobstart(string.format('%s | jq ".searchResult | .[] | .packages | .[] | .id"', command), {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local items = polyfills.tbl_map(function(i)
          local word = i:gsub("\r", ""):gsub("\n", ""):gsub('"', "")
          return { label = word, dup = 0, insertText = word, documentation = "", kind = 11 }
        end, data)
        transformed_callback(items)
      end,
    })
    return
  elseif inside_version then
    local package_name = current_line:match('Include="([^"]+)"')
    local command = cli.package_search(package_name, true, true)
    vim.fn.jobstart(string.format('%s | jq ".searchResult[].packages[].version"', command), {
      stdout_buffered = true,
      on_stdout = function(_, data)
        local index = 0
        local latest = nil
        local last_index = #data - 1
        local items = polyfills.tbl_map(function(i)
          index = index + 1
          local label = i:gsub("\r", ""):gsub("\n", ""):gsub('"', "")
          local cmp_item = {
            label = label,
            insertText = label,
            documentation = "",
            dup = 0,
            kind = 11,
          }
          if index == last_index then latest = cmp_item.label end
          return cmp_item
        end, data)
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
      end,
    })
    return
  end

  transformed_callback({})

  return function() end
end

return M
