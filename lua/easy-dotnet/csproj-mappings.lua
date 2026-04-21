local M = {
  include_pending_cancel_cb = nil,
  version_pending_cancel_cb = nil,
}

local client = require("easy-dotnet.rpc.rpc").global_rpc_client

function M.add_project_reference(curr_project_path, cb)
  client:initialize(function()
    client.project_reference:add_project_reference(curr_project_path, function()
      if cb then cb() end
    end)
  end)
end

local function attach_mappings()
  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    pattern = "*.csproj",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_project_path = vim.api.nvim_buf_get_name(bufnr)

      vim.keymap.set("n", "<leader>ar", function()
        coroutine.wrap(function() M.add_project_reference(curr_project_path) end)()
      end, { buffer = bufnr })
    end,
  })
end

M.package_completion_cmp = {
  complete = function(_, _, callback)
    local _, col = unpack(vim.api.nvim_win_get_cursor(0))
    local current_line = vim.api.nvim_get_current_line()
    local before_cursor = current_line:sub(1, col)
    local package_completion_pattern = 'Include="[^"]*$'
    local version_completion_pattern = 'Version="[^"]*$'

    local inside_include = before_cursor:match(package_completion_pattern)
    local inside_version = before_cursor:match(version_completion_pattern)

    if inside_include then
      local search_term = inside_include:gsub('%Include="', "")
      if M.include_pending_cancel_cb then
        M.include_pending_cancel_cb()
        M.include_pending_cancel_cb = nil
      end
      client:initialize(function()
        M.include_pending_cancel_cb = client.nuget:nuget_search(search_term, nil, function(res)
          local items = vim.tbl_map(function(value) return { label = value.id, kind = 18 } end, res)
          callback({ items = items, isIncomplete = true })
        end).cancel
      end)
    elseif inside_version then
      local package_name = current_line:match('Include="([^"]+)"')

      if M.version_pending_cancel_cb then
        M.version_pending_cancel_cb()
        M.version_pending_cancel_cb = nil
      end
      client:initialize(function()
        M.version_pending_cancel_cb = client.nuget:nuget_get_package_versions(package_name, nil, false, function(res)
          local index = 0
          local latest = nil
          local last_index = #res - 1
          local items = vim.tbl_map(function(i)
            index = index + 1
            local cmp_item = {
              label = i,
              deprecated = true,
              sortText = "",
              preselect = index == last_index,
              kind = 12,
            }
            if index == last_index then latest = cmp_item.label end
            return cmp_item
          end, res)
          if latest then table.insert(items, {
            label = "latest",
            insertText = latest,
            kind = 15,
            preselect = true,
          }) end
          callback({ items = items, isIncomplete = false })
        end).cancel
      end)
    end
  end,

  get_metadata = function(_)
    return {
      priority = 1000,
      filetypes = { "xml", "csproj" },
    }
  end,
}

M.attach_mappings = attach_mappings

return M
