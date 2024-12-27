local M = {}

local polyfills = require("easy-dotnet.polyfills")
local fzf = require("fzf-lua")
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local pickers = require("telescope.pickers")
local picker = require("easy-dotnet.picker")
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

local function reverse_list(list)
  local reversed = {}
  for i = #list, 1, -1 do
    table.insert(reversed, list[i])
  end
  return reversed
end

local function telescope_nuget_search()
  local co = coroutine.running()
  local val
  local opts = {}
  pickers
    .new(opts, {
      prompt_title = "Nuget search",
      finder = finders.new_async_job({
        --TODO: this part sucks I want to use JQ but it seems to be impossible to use it with telescope due to pipes and making OS independent
        command_generator = function(prompt) return { "dotnet", "package", "search", prompt or "", "--format", "json" } end,
        entry_maker = function(line)
          --HACK: ohgod.jpeg
          if line:find('"id":') == nil then return { valid = false } end
          local value = line:gsub('"id": "%s*([^"]+)%s*"', "%1"):match("^%s*(.-)%s*$"):gsub(",", "")
          return {
            value = value,
            ordinal = value,
            display = value,
          }
        end,
        cwd = vim.fn.getcwd(),
      }),
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
    })
    :find()
  coroutine.yield()
  return val
end

---@param cb function
local function fzf_nuget_search(cb)
  fzf.fzf_live('dotnet package search <query> --format json | jq ".searchResult | .[] | .packages | .[] | .id"', {
    fn_transform = function(line) return line:gsub('"', ""):gsub("\r", ""):gsub("\n", "") end,
    actions = {
      ["default"] = function(selected)
        local package = selected[1]
        cb(package)
      end,
    },
  })
end

local function get_all_versions(package)
  local command = string.format("dotnet package search %s --exact-match --format json | jq '.searchResult[].packages[].version'", package)
  local versions = vim.fn.split(vim.fn.system(command):gsub('"', ""), "\n")
  return reverse_list(versions)
end

---@return string
local function get_project()
  local sln_file_path = sln_parse.find_solution_file()
  if not sln_file_path then
    vim.notify("No solution file found", vim.log.levels.ERROR)
    error("No solution file found")
  end
  local projects = sln_parse.get_projects_from_sln(sln_file_path)
  return picker.pick_sync(nil, projects, "Select a project", true).path
end

---@param project_path string | nil
local function add_package(package, project_path)
  print("Getting versions...")
  local versions = polyfills.tbl_map(function(v) return { value = v, display = v } end, get_all_versions(package))

  local selected_version = picker.pick_sync(nil, versions, "Select a version", true)
  vim.notify("Adding package...")
  local selected_project = project_path or get_project()
  local command = string.format("dotnet add %s package %s --version %s", selected_project, package, selected_version.value)
  local co = coroutine.running()
  vim.fn.jobstart(command, {
    on_exit = function(_, ex_code)
      if ex_code == 0 then
        vim.notify("Restoring packages...")
        vim.fn.jobstart(string.format("dotnet restore %s", selected_project), {
          on_exit = function(_, code)
            if code ~= 0 then
              vim.notify("Dotnet restore failed...", vim.log.levels.ERROR)
              --Retry usings users terminal, this will present the error for them. Not sure if this is the correct design choice
              require("easy-dotnet.options").options.terminal(selected_project, "restore", "")
            else
              vim.notify(string.format("Installed %s@%s in %s", package, selected_version.value, vim.fs.basename(selected_project)))
            end
          end,
        })
      else
        vim.notify(string.format("Failed to install %s@%s in %s", package, selected_version.value, vim.fs.basename(selected_project)), vim.log.levels.ERROR)
      end
      coroutine.resume(co)
    end,
  })
  coroutine.yield()
end

---@param project_path string | nil
M.search_nuget = function(project_path)
  -- fzf_nuget_search(on_package_selected)
  local package = telescope_nuget_search()
  add_package(package, project_path)
end

local function get_package_refs(project_path)
  local command = string.format("dotnet list %s package --format json | jq '[.projects[].frameworks[].topLevelPackages[] | {name: .id, version: .resolvedVersion}]'", project_path)
  local out = vim.fn.system(command)
  local packages = vim.fn.json_decode(out)
  print(vim.inspect(packages))
  return packages
end

M.remove_nuget = function()
  local project_path = get_project()
  local packages = get_package_refs(project_path)
  if true then return end
  local choices = polyfills.tbl_map(function()end,)
  local package = picker.pick_sync(nil, packages, "Pick package to remove", false).value
  vim.fn.jobstart(string.format("dotnet remove %s package %s ", project_path, package), {
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Command failed", vim.log.levels.ERROR)
      else
        vim.notify("Package removed " .. package)
        --TODO: dotnet restore F&F
        -- dotnet_restore(M.project, function() discover_package_references(M.project) end)
      end
    end,
  })
end

return M
