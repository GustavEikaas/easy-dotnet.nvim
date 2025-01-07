local M = {}

local picker = require("easy-dotnet.picker")
local fsproj = require("easy-dotnet.parsers.csproj-parse")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")
local polyfills = require("easy-dotnet.polyfills")
local cli = require("easy-dotnet.dotnet_cli")
local logger = require("easy-dotnet.logger")

local function not_in_list(list, value) return not polyfills.tbl_contains(list, value) end

-- Gives a picker for adding a project reference to a fsproject
M.add_project_reference = function(curr_project_path, cb)
  local this_project = fsproj.get_project_from_project_file(curr_project_path)
  local references = fsproj.get_project_references_from_projects(curr_project_path)

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
    local command = cli.add_project(curr_project_path, i.path)
    vim.fn.jobstart(command, {
      on_exit = function(_, code)
        if cb then cb() end
        if code ~= 0 then
          logger.error("Command failed")
        else
          vim.cmd("checktime")
        end
      end,
    })
  end, "Add project reference")
end

local function attach_mappings()
  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    pattern = "*.fsproj",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_project_path = vim.api.nvim_buf_get_name(bufnr)

      -- adds a project reference
      vim.keymap.set("n", "<leader>ar", function() M.add_project_reference(curr_project_path) end, { buffer = bufnr })
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
      local command = cli.package_search(search_term, true, false, 5)
      vim.fn.jobstart(string.format("%s | jq '.searchResult | .[] | .packages | .[] | .id'", command), {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local items = polyfills.tbl_map(function(i) return { label = i:gsub("\r", ""):gsub("\n", ""):gsub('"', ""), kind = 18 } end, data)
          callback({ items = items, isIncomplete = true })
        end,
      })
    elseif inside_version then
      local package_name = current_line:match('Include="([^"]+)"')
      local command = cli.package_search(package_name, true, true)
      vim.fn.jobstart(string.format("%s | jq '.searchResult[].packages[].version'", command), {
        stdout_buffered = true,
        on_stdout = function(_, data)
          local index = 0
          local latest = nil
          local last_index = #data - 1
          local items = polyfills.tbl_map(function(i)
            index = index + 1
            local cmp_item = {
              label = i:gsub("\r", ""):gsub("\n", ""):gsub('"', ""),
              deprecated = true,
              sortText = "",
              preselect = index == last_index,
              kind = 12,
            }
            if index == last_index then latest = cmp_item.label end
            return cmp_item
          end, data)

          if latest then table.insert(items, {
            label = "latest",
            insertText = latest,
            kind = 15,
            preselect = true,
          }) end
          callback({ items = items, isIncomplete = false })
        end,
      })
    end
  end,

  get_metadata = function(_)
    return {
      priority = 1000,
      filetypes = { "xml", "fsproj" },
    }
  end,
}

M.attach_mappings = attach_mappings

return M
