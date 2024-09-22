local M = {}

local picker = require("easy-dotnet.picker")
local csproj = require("easy-dotnet.parsers.csproj-parse")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local error_messages = require("easy-dotnet.error-messages")


local function notInList(list, value)
  for _, it in ipairs(list) do
    if it == value then
      return false
    end
  end
  return true
end

-- Gives a picker for adding a project reference to a csproject
local function add_project_reference(curr_project_path)
  local this_project = csproj.get_project_from_project_file(curr_project_path)
  local references = csproj.get_project_references_from_projects(curr_project_path)

  local solutionFilePath = sln_parse.find_solution_file()
  if solutionFilePath == nil then
    vim.notify(error_messages.no_project_definition_found)
    return
  end

  local all_projects = sln_parse.get_projects_from_sln(solutionFilePath)

  local projects = {}
  -- Ignore current project and already referenced projects
  for _, value in ipairs(all_projects) do
    if value.name ~= this_project.name and notInList(references, value.name) then
      table.insert(projects, value)
    end
  end

  if #projects == 0 then
    vim.notify(error_messages.no_projects_found)
    return
  end

  picker.picker(nil, projects, function(i)
    vim.fn.jobstart(string.format("dotnet add %s reference %s ", curr_project_path, i.path), {
      on_exit = function(_, code)
        if code ~= 0 then
          vim.notify("Command failed")
        else
          vim.cmd('checktime')
        end
      end
    })
  end, "Add project reference")
end


local function attach_mappings()
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    pattern = "*.csproj",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local curr_project_path = vim.api.nvim_buf_get_name(bufnr)

      -- adds a project reference
      vim.keymap.set("n", "<leader>ar", function()
        add_project_reference(curr_project_path)
      end, { buffer = bufnr })
    end
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
      vim.fn.jobstart(
        string.format(
          "dotnet package search %s --take 5 --format json | jq '.searchResult | .[] | .packages | .[] | .id'",
          search_term), {
          stdout_buffered = true,
          on_stdout = function(_, data)
            local items = vim.tbl_map(function(i)
              return { label = i:gsub("\r", ""):gsub("\n", ""):gsub('"', ""), kind = 18 }
            end, data)
            callback({ items = items, isIncomplete = true })
          end,
        })
    elseif inside_version then
      local package_name = current_line:match('Include="([^"]+)"')
      vim.fn.jobstart(
        string.format(
          "dotnet package search %s --exact-match --format json | jq '.searchResult[].packages[].version'", package_name),
        {
          stdout_buffered = true,
          on_stdout = function(_, data)
            local index = 0
            local latest = nil
            local last_index = #data - 1
            local items = vim.tbl_map(function(i)
              index = index + 1
              local cmp_item = {
                label = i:gsub("\r", ""):gsub("\n", ""):gsub('"', ""),
                deprecated = true,
                sortText = "",
                preselect = index == last_index,
                kind = 12
              }
              if index == last_index then
                latest = cmp_item.label
              end
              return cmp_item
            end, data)

            if latest then
              table.insert(items, {
                label = "latest",
                insertText = latest,
                kind = 15,
                preselect = true
              })
            end
            callback({ items = items, isIncomplete = false })
          end,
        })
    end
  end,

  get_metadata = function(_)
    return {
      priority = 1000,
      filetypes = { 'xml', 'csproj' },
    }
  end
}

M.attach_mappings = attach_mappings

return M
