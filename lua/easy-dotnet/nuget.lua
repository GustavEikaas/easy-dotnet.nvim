local M = {}


local function wrap(callback)
  return function(...)
    -- Check if we are already in a coroutine
    if coroutine.running() then
      -- If already in a coroutine, call the callback directly
      callback(...)
    else
      -- If not, create a new coroutine and resume it
      local co = coroutine.create(callback)
      coroutine.resume(co, ...)
    end
  end
end

local function reverse_list(list)
  local reversed = {}
  for i = #list, 1, -1 do
    table.insert(reversed, list[i])
  end
  return reversed
end

local fzf = require('fzf-lua')
local sln_parse = require("easy-dotnet.parsers.sln-parse")
local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local conf = require('telescope.config').values

---@param cb function
local function telescope_nuget_search(cb)
  local opts = {}

  pickers.new(opts, {
    prompt_title = "Nuget search",
    finder = finders.new_async_job {
      --TODO: this part sucks I want to use JQ but it seems to be impossible to use it with telescope due to pipes
      command_generator = function(prompt)
        if prompt and prompt ~= "" then
          return { "dotnet", "package", "search", prompt, "--format", "json" }
        else
          return { "dotnet", "package", "search", "--format", "json" }
        end
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
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        cb(selection.value)
      end)
      return true
    end,
  }):find()
end

---@param cb function
local function telescope_fzf_search(cb)
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

local function on_package_selected(package)
  local versions = vim.fn.split(vim.fn.system('dotnet package search ' ..
    package .. ' --exact-match --format json | jq \'.searchResult[].packages[].version\''):gsub('"', ''), '\n')
  local reversed_versions = reverse_list(versions)
  vim.ui.select(reversed_versions, { prompt = "Select a version" }, function(selected_version)
    local sln_file_path = sln_parse.find_solution_file()
    if not sln_file_path then
      vim.notify("No solution file found")
      return
    end
    local projects = sln_parse.get_projects_from_sln(sln_file_path)
    require("easy-dotnet.picker").picker(nil, projects, function(selected_project)
      vim.fn.jobstart(
        "dotnet add " .. selected_project.path .. " package " .. package .. " --version " .. selected_version, {
          on_exit = function(_, code)
            if code == 0 then
              vim.notify("Installed " .. package .. "@" .. selected_version .. " in " .. selected_project.display)
            else
              vim.notify("Failed to install " ..
                package .. "@" .. selected_version .. " in " .. selected_project.display, vim.log.levels.ERROR)
            end
          end
        })
    end, "Select a project", true)
  end)
end

M.search_nuget = function()
  telescope_nuget_search(on_package_selected)
end

vim.api.nvim_create_user_command('NS', function()
  wrap(function()
    M.search_nuget()
  end)()
end, {
  nargs = 0,
  complete = nil,
})

return M
