local M = {}

local polyfills = require "easy-dotnet.polyfills"
local fzf = require('fzf-lua')
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local pickers = require('telescope.pickers')
local picker = require("easy-dotnet.picker")
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values

local function reverse_list(list)
  local reversed = {}
  for i = #list, 1, -1 do
    table.insert(reversed, list[i])
  end
  return reversed
end

---@param cb function
local function telescope_nuget_search()
  local co = coroutine.running()
  local val
  local opts = {}
  pickers.new(opts, {
    prompt_title = "Nuget search",
    finder = finders.new_async_job {
      --TODO: this part sucks I want to use JQ but it seems to be impossible to use it with telescope due to pipes and making OS independent
      command_generator = function(prompt)
        return { "dotnet", "package", "search", prompt or "", "--format", "json" }
      end,
      entry_maker = function(line)
        --HACK: ohgod.jpeg
        if line:find("id") == nil then
          return { valid = false }
        end
        local value = line:gsub('"id": "%s*([^"]+)%s*"', "%1"):match("^%s*(.-)%s*$"):gsub(",", "")
        return {
          value = value,
          ordinal = value,
          display = value,
        }
      end,
      cwd = vim.fn.getcwd()
    },
    sorter = conf.generic_sorter(opts),
    attach_mappings = function()
      actions.select_default:replace(function(prompt_bufnr)
        local selection = action_state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        val = selection.value
        coroutine.resume(co)
      end)
      return true
    end,
  }):find()
  coroutine.yield()
  return val
end

---@param cb function
local function fzf_nuget_search(cb)
  fzf.fzf_live("dotnet package search <query> --format json | jq \".searchResult | .[] | .packages | .[] | .id\"", {
    fn_transform = function(line)
      return line:gsub('"', ''):gsub("\r", ""):gsub("\n", "")
    end,
    actions = {
      ['default'] = function(selected)
        local package = selected[1]
        cb(package)
      end,
    },

  })
end

local function get_all_versions(package)
  local command = string.format(
    'dotnet package search %s --exact-match --format json | jq \'.searchResult[].packages[].version\'', package)
  local versions = vim.fn.split(
    vim.fn.system(command):gsub('"', ''), '\n')
  return reverse_list(versions)
end

local function on_package_selected(package)
  local versions = polyfills.tbl_map(function(v)
    return { value = v, display = v }
  end, get_all_versions(package))

  local selected_version = picker.pick_sync(nil, versions, "Select a version", true)
  local sln_file_path = sln_parse.find_solution_file()
  if not sln_file_path then
    vim.notify("No solution file found")
    return
  end
  local projects = sln_parse.get_projects_from_sln(sln_file_path)
  local selected_project = picker.pick_sync(nil, projects, "Select a project", true)
  local command = string.format("dotnet add %s package %s --version %s", selected_project.path, package,
    selected_version.value)
  vim.fn.jobstart(command, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify(string.format("Installed %s@%s in %s", package, selected_version.value, selected_project.display))
      else
        vim.notify(
          string.format("Failed to install %s@%s in %s", package, selected_version.value, selected_project.display),
          vim.log.levels.ERROR)
      end
    end
  })
end

M.search_nuget = function()
  -- fzf_nuget_search(on_package_selected)
  local package = telescope_nuget_search()
  on_package_selected(package)
end

return M
