local M = {}

local rpc = require("easy-dotnet.rpc.rpc")
local diagnostics = require("easy-dotnet.diagnostics")
local sln_parser = require("easy-dotnet.parsers.sln-parse")
local constants = require("easy-dotnet.constants")
local current_solution = require("easy-dotnet.current_solution")
local external_access = require("easy-dotnet.roslyn.lsp.external_access")
local jobs = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")

local function get_default_filter()
  return function(filename) return (filename:match("%.cs$") or filename:match("%.fs$")) and not filename:match("/obj/") and not filename:match("/bin/") end
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

local workspace_diagnostics_handler = "EasyDotnet.RoslynLanguageServices.Diagnostics.WorkspaceDiagnosticsMessageHandler"

local function absolute_path(path) return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")) end

---Roslyn only has the selected solution loaded, so other solutions go through the server
---@return vim.lsp.Client|nil
local function find_roslyn_client(selected_item)
  if not external_access.is_enabled(require("easy-dotnet.options").options.lsp) then return nil end

  local target = absolute_path(selected_item.value)
  if selected_item.type == "solution" then
    local loaded_solution = current_solution.try_get_selected_solution()
    if not loaded_solution or absolute_path(loaded_solution) ~= target then return nil end
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = constants.lsp_client_name })) do
    if client.root_dir and vim.fs.relpath(client.root_dir, target) then return client end
  end
  return nil
end

local function request_from_server(target_path, include_warnings, finish)
  rpc.global_rpc_client.roslyn:get_workspace_diagnostics(target_path, include_warnings, function(response)
    finish(true)
    diagnostics.populate_diagnostics(response, get_default_filter())
  end, {
    job = false,
    on_crash = function(err) finish(false, { err and err.message or "Unknown error" }) end,
  })
end

local function execute_diagnostics_request(selected_item, include_warnings)
  if not selected_item or not selected_item.value or selected_item.value == "" then
    vim.notify("Invalid project/solution path", vim.log.levels.ERROR)
    return
  end

  local finish = jobs.register_job({
    name = "Getting workspace diagnostics...",
    on_error_text = "Failed to get diagnostics",
    on_success_text = "Diagnostics retrieved",
  })

  local client = find_roslyn_client(selected_item)
  if not client then
    request_from_server(selected_item.value, include_warnings, finish)
    return
  end

  external_access.dispatch_workspace(client, workspace_diagnostics_handler, {
    targetPath = absolute_path(selected_item.value),
    includeWarnings = include_warnings,
  }, function(err, response)
    if err or not response or response.projectCount == 0 then
      if err then logger.warn("[easy-dotnet] Roslyn workspace diagnostics failed, falling back to server: " .. (type(err) == "table" and (err.message or err.Message) or tostring(err))) end
      request_from_server(selected_item.value, include_warnings, finish)
      return
    end

    finish(true)
    diagnostics.populate_diagnostics(response.diagnostics, get_default_filter())
  end)
end

---@param severity_filter? "error"|"warning"
function M.get_workspace_diagnostics(severity_filter)
  -- Use configured default if no severity filter is provided
  if not severity_filter then severity_filter = require("easy-dotnet.options").options.diagnostics.default_severity end

  local include_warnings = get_severity_params(severity_filter)

  rpc.global_rpc_client:initialize(function()
    sln_parser.find_project_files(function(projects)
      sln_parser.get_solutions(function(solutions)
        local all_items = {}

        -- Add solutions first to prioritize them in the picker
        for _, solution in ipairs(solutions) do
          table.insert(all_items, {
            display = "Solution: " .. vim.fn.fnamemodify(solution, ":t"),
            value = solution,
            type = "solution",
          })
        end

        for _, project in ipairs(projects) do
          table.insert(all_items, {
            display = "Project: " .. vim.fn.fnamemodify(project, ":t"),
            value = project,
            type = "project",
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
            if selected then execute_diagnostics_request(selected, include_warnings) end
          end, "Select project or solution for diagnostics:")
        end
      end)
    end)
  end)
end

return M
