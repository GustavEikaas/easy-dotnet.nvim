local M = {
  include_pending = nil,
  version_pending = nil,
}

local picker = require("easy-dotnet.picker")
local client = require("easy-dotnet.rpc.rpc").global_rpc_client
local polyfills = require("easy-dotnet.polyfills")
local csproj = require("easy-dotnet.parsers.csproj-parse")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local logger = require("easy-dotnet.logger")

local function not_in_list(list, value) return not polyfills.tbl_contains(list, value) end

-- Gives a picker for adding a project reference to a csproject
function M.add_project_reference(curr_project_path, cb)
  local this_project = csproj.get_project_from_project_file(curr_project_path)
  local references = csproj.get_project_references_from_projects(curr_project_path)

  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    logger.error(error_messages.no_project_definition_found)
    return false
  end

  local all_projects = sln_parse.get_projects_from_sln(solutionFilePath)

  local projects = {}
  -- Ignore current project and already referenced projects
  for _, value in ipairs(all_projects) do
    if value.name ~= this_project.name and not_in_list(references, value.name) then table.insert(projects, value) end
  end

  if #projects == 0 then
    logger.error(error_messages.no_projects_found)
    return false
  end

  picker.picker(nil, projects, function(i)
    client:initialize(function()
      client:msbuild_add_project_reference(curr_project_path, i.path, function(res)
        if cb then cb() end
        if res == false then
          logger.error("Command failed")
        else
          vim.cmd("checktime")
        end
      end)
    end)
  end, "Add project reference")
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
      if M.include_pending then
        client._client.cancel(M.include_pending)
        M.include_pending = nil
      end
      client:initialize(function()
        M.include_pending = client:nuget_search(search_term, nil, function(res)
          local items = polyfills.tbl_map(function(value) return { label = value.id, kind = 18 } end, res)
          callback({ items = items, isIncomplete = true })
        end)
      end)
    elseif inside_version then
      local package_name = current_line:match('Include="([^"]+)"')

      if M.version_pending then
        client._client.cancel(M.version_pending)
        M.version_pending = nil
      end
      client:initialize(function()
        M.version_pending = client:nuget_get_package_versions(package_name, nil, false, function(res)
          local index = 0
          local latest = nil
          local last_index = #res - 1
          local items = polyfills.tbl_map(function(i)
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
        end)
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
