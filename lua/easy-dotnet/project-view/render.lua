local ns_id = require("easy-dotnet.constants").ns_id
local polyfills = require("easy-dotnet.polyfills")

---@class ProjectWindow
---@field jobs table
---@field appendJob table
---@field buf integer | nil
---@field win integer | nil
---@field height integer
---@field modifiable boolean
---@field buf_name string
---@field filetype string
---@field keymap table
---@field options table
---@field project_refs table

local M = {
  lines = {},
  project_refs = { "Loading..." },
  package_refs = { "Loading..." },
  project = nil,
  jobs = {},
  append_job = nil,
  buf = nil,
  win = nil,
  height = 10,
  modifiable = false,
  buf_name = "",
  filetype = "",
  keymap = {},
  options = {},
}

M.keymap = {
  ["q"] = function() M.hide() end,
}

---@param output string[]
---@returns string[]
local function extract_projects(output)
  local projects = {}
  for _, value in ipairs(output) do
    local sanitized = value:gsub("\n", ""):gsub("\r", "")
    if sanitized:match("%.csproj$") or sanitized:match("%.fsproj$") then table.insert(projects, sanitized) end
  end

  return projects
end

---@param project DotnetProject
local function discover_project_references(project)
  local finished = M.append_job("Discovering project references")

  vim.fn.jobstart({ "dotnet", "list", project.path, "reference" }, {
    stdout_buffered = true,
    on_exit = function(_, code)
      finished()
      M.refresh()
      if code ~= 0 then return end
    end,
    on_stdout = function(_, data, _)
      local projects = extract_projects(data)
      if #projects == 0 then
        M.project_refs = nil
      else
        M.project_refs = projects
      end
    end,
  })
end

local function dotnet_restore(project, cb)
  local finished = M.append_job("Restoring packages")
  vim.fn.jobstart({ "dotnet", "restore", project.path }, {
    on_exit = function(_, code)
      finished()
      M.refresh()
      cb()
      if code ~= 0 then
        vim.notify("Dotnet restore failed", vim.log.levels.ERROR)
        return
      end
    end,
  })
end

---@param project DotnetProject
local function discover_package_references(project)
  local finished = M.append_job("Discovering package references")
  --Incase of out of mem, do some jq tricks to read line by line
  --TODO: research the frameworks[]
  --TODO: is it possible to resolve transitive dependencies?
  local command = string.format("dotnet list %s package --format json | jq '[.projects[].frameworks[].topLevelPackages[] | {name: .id, version: .resolvedVersion}]'", project.path)
  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code)
      finished()
      M.refresh()
      if code ~= 0 then return end
    end,
    on_stdout = function(_, data, _)
      local package_refs = {}
      local packages = vim.fn.json_decode(data)
      for _, v in ipairs(packages) do
        table.insert(package_refs, string.format("%s@%s", v.name, v.version))
      end
      M.package_refs = package_refs
    end,
  })
end

---@param id string
function M.append_job(id)
  local job = { id = id }
  table.insert(M.jobs, job)
  M.refresh()

  local on_job_finished_callback = function()
    job.completed = true
    local is_all_finished = polyfills.iter(M.jobs):all(function(s) return s.completed end)
    if is_all_finished == true then M.jobs = {} end
    M.refresh()
  end

  return on_job_finished_callback
end

function M.redraw_virtual_text()
  if #M.jobs > 0 then
    local current_job = M.jobs[1].id
    vim.api.nvim_buf_set_extmark(M.buf, ns_id, 0, 0, {
      virt_text = { { current_job, "Character" } },
      virt_text_pos = "right_align",
      priority = 200,
    })
  end
end

local function set_buffer_options()
  vim.api.nvim_win_set_height(M.win, M.height)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)
  vim.api.nvim_buf_set_name(M.buf, M.buf_name)
  vim.api.nvim_buf_set_option(M.buf, "filetype", M.filetype)
  --Crashes on nvim 0.9.5??
  -- vim.api.nvim_buf_set_option(M.buf, "cursorline", true)
end

---@param highlights Highlight[]
local function apply_highlights(highlights)
  for _, value in ipairs(highlights) do
    if value.highlight ~= nil then vim.api.nvim_buf_add_highlight(M.buf, ns_id, value.highlight, value.index - 1, 0, -1) end
  end
end

---@param args table<table<string,string>>
local function build_structure(args)
  local struct = {}
  local highlights = {}
  local keymaps = {}
  for i, s in ipairs(args) do
    local text = s[1]
    local highlight = s[2] or nil
    local keymap = s[3] or nil
    table.insert(struct, text)
    if highlight then table.insert(highlights, { index = i, highlight = highlight }) end
    if keymap then table.insert(keymaps, { index = i, keymap = keymap }) end
  end
  return struct, highlights, keymaps
end

local sep = { "" }
local function open_browser(url)
  if vim.fn.has("mac") == 1 then
    vim.fn.system("open " .. url)
  elseif vim.fn.has("unix") == 1 then
    vim.fn.system("xdg-open " .. url)
  elseif vim.fn.has("win32") == 1 then
    vim.fn.system("start " .. url)
  else
    error("Unknown OS, please raise an issue")
    return
  end
end

local function open_package_browser_keymap(ref)
  return {
    --TODO: customize keybindings
    key = "<C-b>",
    handler = function()
      local package_name = ref:match("^(.-)@")
      --TODO: determine which feed the package comes from
      open_browser("https://www.nuget.org/packages/" .. package_name)
    end,
  }
end

local function remove_package_keymap(ref)
  return {
    --TODO: customize keybindings
    key = "r",
    handler = function()
      local cleanup = M.append_job("Removing package " .. ref)
      local package_name = ref:match("^(.-)@")
      vim.fn.jobstart(string.format("dotnet remove %s package %s ", M.project.path, package_name), {
        on_exit = function(_, code)
          cleanup()
          if code ~= 0 then
            vim.notify("Command failed", vim.log.levels.ERROR)
          else
            vim.notify("Package removed " .. package_name)
            dotnet_restore(M.project, function() discover_package_references(M.project) end)
          end
        end,
      })
    end,
  }
end

local function add_package_keymap()
  return {
    key = "a",
    handler = function()
      require("easy-dotnet.nuget").search_nuget(M.project.path)
      discover_package_references(M.project)
    end,
  }
end

local function add_project_keymap()
  return {
    key = "a",
    handler = function()
      --HACK: fix this
      local cleanup = nil
      local add = M.project.language == "csharp" and require("easy-dotnet.csproj-mappings").add_project_reference or require("easy-dotnet.fsproj-mappings").add_project_reference
      local res = add(M.project.path, function()
        if cleanup then cleanup() end
        discover_project_references(M.project)
      end)
      if res ~= false then cleanup = M.append_job("Adding project reference") end
    end,
  }
end

local function remove_project_keymap(ref)
  return {
    key = "r",
    handler = function()
      local cleanup = M.append_job("Removing project reference")
      vim.fn.jobstart(string.format("dotnet remove %s reference %s ", M.project.path, ref), {
        on_exit = function(_, code)
          cleanup()
          if code ~= 0 then
            vim.notify("Command failed", vim.log.levels.ERROR)
          else
            vim.notify("Project removed " .. ref)
            discover_project_references(M.project)
          end
        end,
      })
    end,
  }
end

local function stringify_project_header()
  local project = M.project
  local sln_path = M.sln_path
  if not project then return { "No project selected" }, {} end

  local args = {
    { string.format("Project: %s", project.name), "Character" },
    { string.format("Version: %s", project.version), "Question" },
    { string.format("Language: %s", project.language == "csharp" and "C#" or project.language == "fsharp" and "F#" or "Unknown"), "Question" },
    { string.format("Type: %s", project.isWebProject and "Web" or project.isConsoleProject and "Console" or project.isTestProject and "Test" or "Unknown"), "Question" },
    sln_path and { string.format("Solution: %s", vim.fn.fnamemodify(sln_path, ":t")), "Question" } or nil,
    sep,
    { "Project References: (a)dd (r)emove", "Character", { add_project_keymap() } },
  }

  if not M.project_refs then
    table.insert(args, { "  None", "Question", { add_project_keymap() } })
  else
    for _, ref in ipairs(M.project_refs) do
      table.insert(args, { string.format("  %s", vim.fs.basename(ref)), "Question", { remove_project_keymap(ref), add_project_keymap() } })
    end
  end

  table.insert(args, sep)
  table.insert(args, { "Package References: (a)dd (r)emove", "Character" })

  if not M.package_refs then
    table.insert(args, { "  None", "Question" })
  else
    for _, ref in ipairs(M.package_refs) do
      table.insert(args, { string.format("  %s", ref), "Question", { add_package_keymap(), remove_package_keymap(ref), open_package_browser_keymap(ref) } })
    end
  end

  return build_structure(args)
end

local function stringify()
  local project = M.project
  if not project then return { "No project selected" }, {} end
  return stringify_project_header()
end

local function print_lines()
  vim.api.nvim_buf_clear_namespace(M.buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", true)
  local stringLines, highlights, keymaps = stringify()
  vim.api.nvim_buf_set_lines(M.buf, 0, -1, true, stringLines)
  vim.api.nvim_buf_set_option(M.buf, "modifiable", M.modifiable)

  if keymaps ~= nil then
    local keys = {}
    for _, value in ipairs(keymaps) do
      for _, keymap in ipairs(value.keymap) do
        keys[keymap.key] = keymap.key
      end
    end

    --Register all keymaps
    for key, _ in pairs(keys) do
      vim.keymap.set("n", key, function()
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        for _, value in ipairs(keymaps) do
          --Ensure keymap is valid for current line
          if value.index == current_line then
            for _, keymap in ipairs(value.keymap) do
              --Ensure keymap is valid for current key
              if keymap.key == key then coroutine.wrap(function() keymap.handler() end)() end
            end
          end
        end
      end, { silent = true, noremap = true })
    end
  end

  M.redraw_virtual_text()
  apply_highlights(highlights)
end

local function set_mappings()
  if M.keymap == nil then return end
  if M.buf == nil then return end
  for key, value in pairs(M.keymap) do
    vim.keymap.set("n", key, function() value() end, { buffer = M.buf, noremap = true, silent = true })
  end
end

M.set_keymaps = function(mappings)
  M.keymap = mappings
  set_mappings()
  return M
end

---@param options TestRunnerOptions
M.set_options = function(options)
  if options then M.options = options end
  return M
end

local function get_default_win_opts()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  M.height = height

  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
  }
end

-- Toggle function to handle different window modes
-- Function to hide the window or buffer based on the mode
function M.hide()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, false)
    M.win = nil
    return true
  end
  return false
end

function M.close()
  if M.buf then
    vim.api.nvim_buf_delete(M.buf, { force = true })
    M.buf = nil
  end
end

function M.open()
  if not M.buf then M.buf = vim.api.nvim_create_buf(false, true) end
  local win_opts = get_default_win_opts()
  M.win = vim.api.nvim_open_win(M.buf, true, win_opts)
  vim.api.nvim_buf_set_option(M.buf, "bufhidden", "hide")
  return true
end

function M.toggle()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    return not M.hide()
  else
    return M.open()
  end
end

local function window_destroy()
  if M.win and vim.api.nvim_win_is_valid(M.win) then vim.api.nvim_win_close(M.win, true) end
  M.win = nil
end

---@param project DotnetProject
---@param sln_path string | nil
M.render = function(project, sln_path)
  window_destroy()
  M.project = project
  M.sln_path = sln_path
  local isVisible = M.toggle()
  if not isVisible then return end

  discover_project_references(project)
  dotnet_restore(project, function() discover_package_references(project) end)

  print_lines()
  set_buffer_options()
  set_mappings()
  return M
end

M.refresh_mappings = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  set_mappings()
  return M
end

--- Refreshes the buffer if lines have changed
M.refresh = function()
  if M.buf == nil then error("Can not refresh buffer before render() has been called") end
  print_lines()
  set_buffer_options()
  return M
end

return M
