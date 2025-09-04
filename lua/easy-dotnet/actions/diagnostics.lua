local M = {}

local rpc = require("easy-dotnet.rpc.rpc")
local diagnostics = require("easy-dotnet.diagnostics")
local parsers = require("easy-dotnet.parsers")

local function get_default_filter()
  return function(filename)
    return (filename:match("%.cs$") or filename:match("%.fs$")) and not filename:match("/obj/") and not filename:match("/bin/")
  end
end

---@param severity_filter "error"|"warning"
local function get_severity_params(severity_filter)
  if severity_filter == "error" then
    return false
  elseif severity_filter == "warning" then
    return true
  else
    error("Invalid severity filter: " .. tostring(severity_filter))
  end
end

local function execute_diagnostics_request(selected_item, include_warnings)
  rpc.global_rpc_client:get_workspace_diagnostics(
    selected_item.value,
    include_warnings,
    function(response)
      diagnostics.populate_diagnostics(response, get_default_filter())
    end
  )
end

---@param severity_filter "error"|"warning"
function M.get_workspace_diagnostics(severity_filter)
  local include_warnings = get_severity_params(severity_filter)
  
  rpc.global_rpc_client:initialize(function()
    local projects = parsers.sln_parser.find_project_files()
    local solutions = parsers.sln_parser.get_solutions()
    
    local all_items = {}
    
    for _, project in ipairs(projects) do
      table.insert(all_items, {
        display = "Project: " .. vim.fn.fnamemodify(project, ":t"),
        value = project,
        type = "project"
      })
    end
    
    for _, solution in ipairs(solutions) do
      table.insert(all_items, {
        display = "Solution: " .. vim.fn.fnamemodify(solution, ":t"),
        value = solution,
        type = "solution"
      })
    end
    
    if #all_items == 0 then
      vim.notify("No .csproj or .sln files found in the workspace", vim.log.levels.WARN)
      return
    end
    
    if #all_items == 1 then
      local selected = all_items[1]
      execute_diagnostics_request(selected, include_warnings)
    else
      local picker = require("easy-dotnet.picker")
      picker.picker(nil, all_items, function(selected)
        if selected then
          execute_diagnostics_request(selected, include_warnings)
        end
      end, "Select project or solution for diagnostics:")
    end
  end)
end

return M