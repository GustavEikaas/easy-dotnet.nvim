local current_solution = require("easy-dotnet.current_solution")
local M = {
  pending = false,
}

local logger = require("easy-dotnet.logger")
local parsers = require("easy-dotnet.parsers")
local csproj_parse = parsers.csproj_parser
local error_messages = require("easy-dotnet.error-messages")
local qf_list = require("easy-dotnet.build-output.qf-list")

local function group_by_project(errors)
  return vim.iter(errors):fold({}, function(acc, err)
    local project = err.project or "Unknown project"
    acc[project] = acc[project] or {}
    table.insert(acc[project], err)
    return acc
  end)
end

function M.rpc_build_quickfix(target_path, configuration, args, cb)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client

  if M.pending == true then
    logger.error("Build already pending...")
    return
  end

  current_solution.get_or_pick_solution(function(solution_path)
    solution_path = solution_path or csproj_parse.find_project_file()
    if solution_path == nil then
      logger.error(error_messages.no_project_definition_found)
      return
    end

    client:initialize(function()
      M.pending = true
      client.msbuild:msbuild_build({ targetPath = target_path, configuration = configuration, buildArgs = args }, function(res)
        local ext = vim.fn.fnamemodify(target_path, ":e")
        local is_solution = ext == "sln" or ext == "slnx"
        M.pending = false
        if cb then cb(res.success) end
        if res.success then
          if is_solution then
            qf_list.clear_all()
          else
            qf_list.clear_project(target_path)
          end
          return
        end

        if is_solution then qf_list.clear_all() end
        local project_map = group_by_project(res.errors)
        for project, diagnostics in pairs(project_map) do
          qf_list.set_project_diagnostics(project, diagnostics)
        end
      end)
    end)
  end)
end

return M
