local M = {}

M.projects = {}
M.qf_title = "Easy Dotnet | Build Output"

--- Convert diagnostics to quickfix items
---@param diagnostics table[]
---@return table[]
local function diagnostics_to_qf(diagnostics)
  local items = {}
  for _, d in ipairs(diagnostics) do
    table.insert(items, {
      filename = d.filePath,
      lnum = tonumber(d.lineNumber) or 1,
      col = tonumber(d.columnNumber) or 1,
      text = d.message,
      type = (d.type == "error" or d.type == "E") and "E" or "W",
    })
  end
  return items
end

--- Check if we own the quickfix list
---@return boolean
local function owns_quickfix()
  local info = vim.fn.getqflist({ title = 1 })
  return info.title == M.qf_title
end

--- Refresh quickfix window with all project errors
local function refresh_quickfix()
  local all_items = {}
  for project, diags in pairs(M.projects) do
    table.insert(all_items, {
      filename = "",
      lnum = 0,
      col = 0,
      text = string.format("==== %s ====", project),
      type = "I",
    })

    local items = diagnostics_to_qf(diags)
    for _, item in ipairs(items) do
      table.insert(all_items, item)
    end
  end

  if vim.tbl_isempty(all_items) then
    if owns_quickfix() then
      vim.fn.setqflist({})
      vim.cmd("cclose")
    end
  else
    vim.fn.setqflist({}, " ", {
      title = M.qf_title,
      items = all_items,
    })
    vim.cmd("copen")
  end
end

--- Normalize project identifier
--- If it's a valid path to a .csproj, extract its basename.
--- Otherwise, use the input string as the project name.
---@param project string
---@return string
local function normalize_project_name(project)
  if not project or project == "" then return "" end

  local expanded = vim.fn.fnamemodify(project, ":p")
  if vim.fn.filereadable(expanded) == 1 then
    local ext = vim.fn.fnamemodify(expanded, ":e")
    if ext == "csproj" then return vim.fn.fnamemodify(expanded, ":t:r") end
  end

  return project
end

--- Add or replace diagnostics for a project (or .csproj path)
---@param project string
---@param diagnostics table[]
function M.set_project_diagnostics(project, diagnostics)
  local name = normalize_project_name(project)
  M.projects[name] = diagnostics or {}
  refresh_quickfix()
end

--- Clear diagnostics for a single project (or .csproj path)
---@param project string
function M.clear_project(project)
  local name = normalize_project_name(project)
  M.projects[name] = nil
  refresh_quickfix()
end

function M.clear_all()
  M.projects = {}
  refresh_quickfix()
end

return M
