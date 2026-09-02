local M = {}

---@type string|nil  absolute path of the project currently shown
M.project_path = nil

---@type easy-dotnet.ProjectView.Snapshot|nil
M.snapshot = nil

---@type boolean  true while a server operation is in flight (drives the spinner)
M.loading = false

---@type string|nil  short text describing the in-flight operation
M.operation = nil

---@param project_path string
---@param snapshot easy-dotnet.ProjectView.Snapshot
function M.set(project_path, snapshot)
  M.project_path = project_path
  M.snapshot = snapshot
end

function M.clear()
  M.project_path = nil
  M.snapshot = nil
  M.loading = false
  M.operation = nil
end

---@param is_loading boolean
---@param operation string|nil
function M.set_status(is_loading, operation)
  M.loading = is_loading
  M.operation = operation
end

---@class easy-dotnet.ProjectView.Row
---@field kind "meta"|"section"|"package"|"projectref"|"empty"|"none"
---@field section "packages"|"projectrefs"|nil
---@field pkg easy-dotnet.ProjectView.Package|nil
---@field ref easy-dotnet.ProjectView.ProjectRef|nil
---@field label string|nil
---@field count integer|nil
---@field selectable boolean

---@return easy-dotnet.ProjectView.Row[]
function M.build_rows()
  local rows = {}
  if not M.snapshot then return rows end

  local snap = M.snapshot

  table.insert(rows, { kind = "meta", selectable = false })
  table.insert(rows, { kind = "none", selectable = false })

  table.insert(rows, { kind = "section", section = "packages", label = "Packages", count = #snap.packages, selectable = true })
  if #snap.packages == 0 then
    table.insert(rows, { kind = "empty", section = "packages", selectable = false })
  else
    for _, pkg in ipairs(snap.packages) do
      table.insert(rows, { kind = "package", section = "packages", pkg = pkg, selectable = true })
    end
  end

  table.insert(rows, { kind = "none", selectable = false })

  table.insert(rows, { kind = "section", section = "projectrefs", label = "Project References", count = #snap.projectReferences, selectable = true })
  if #snap.projectReferences == 0 then
    table.insert(rows, { kind = "empty", section = "projectrefs", selectable = false })
  else
    for _, ref in ipairs(snap.projectReferences) do
      table.insert(rows, { kind = "projectref", section = "projectrefs", ref = ref, selectable = true })
    end
  end

  return rows
end

return M
