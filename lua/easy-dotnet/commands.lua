local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
---@type table<string,easy-dotnet.Command>
local M = {}

---@class easy-dotnet.Command
---@field subcommands table<string,easy-dotnet.Command> | nil
---@field handle nil | fun(args: table<string>|string, options: table): nil
---@field passthrough boolean | nil
---@field desc string | nil Shown in the generated command and Lua API docs
---@field args string | nil Argument placeholder shown in the docs, e.g. "<path>"

---@class easy-dotnet.PassthroughArgs
---@field configuration string | nil Build configuration the user asked for, if any
---@field args string | nil Remaining arguments, verbatim

---@param arguments table<string>| nil | string
---@param scope "dotnet" | "app"
---@return easy-dotnet.PassthroughArgs
local function parse_passthrough_args(arguments, scope)
  if type(arguments) == "string" then return { args = arguments } end
  if not arguments or #arguments == 0 then return {} end

  local configuration = nil
  local rest = {}
  local index = 1

  while index <= #arguments do
    local argument = arguments[index]
    local lowered = argument:lower()
    local is_shorthand = lowered == "release" or lowered == "debug"
    local is_flag = lowered == "-c" or lowered == "--configuration"

    if configuration == nil and index == 1 and is_shorthand then
      -- Shorthand dotnet build release -> dotnet build -c Release
      configuration = lowered:sub(1, 1):upper() .. lowered:sub(2)
      index = index + 1
    elseif configuration == nil and (scope == "dotnet" or index == 1) and is_flag and arguments[index + 1] then
      configuration = arguments[index + 1]
      index = index + 2
    else
      table.insert(rest, argument)
      index = index + 1
    end
  end

  return { configuration = configuration, args = #rest > 0 and table.concat(rest, " ") or nil }
end

local actions = require("easy-dotnet.actions")

---This entire object is exposed, any change to this will possibly be a breaking change, tread carefully
---@type easy-dotnet.Command
M.run = {
  desc = "`dotnet run --project <Picker> <DArgs>`",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "app")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:run({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = parsed.args,
          configuration = parsed.configuration,
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      desc = "`dotnet run --project <Picker Default> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "app")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:run({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = parsed.args,
              configuration = parsed.configuration,
            })
          end
        )
      end,
      passthrough = true,
    },
    profile = {
      desc = "`dotnet run --project <Picker> --launch-profile <Picker> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "app")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:run({
              use_default = false,
              use_launch_profile = true,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = parsed.args,
              configuration = parsed.configuration,
            })
          end
        )
      end,
      passthrough = true,
      subcommands = {
        default = {
          desc = "`dotnet run --project <Picker Default> --launch-profile <Picker> <DArgs>`",
          handle = function(args, _)
            local parsed = parse_passthrough_args(args, "app")
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(
              function()
                client.workspace:run({
                  use_default = true,
                  use_launch_profile = true,
                  file_path = vim.api.nvim_buf_get_name(0),
                  cli_args = parsed.args,
                  configuration = parsed.configuration,
                })
              end
            )
          end,
          passthrough = true,
        },
      },
    },
  },
}

M.debug = {
  desc = "Debug selected project",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "app")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:debug({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = parsed.args,
          configuration = parsed.configuration,
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      desc = "Debug the persisted default project",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "app")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:debug({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = parsed.args,
              configuration = parsed.configuration,
            })
          end
        )
      end,
      passthrough = true,
    },
    profile = {
      desc = "Debug selected project with selected launch profile",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "app")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:debug({
              use_default = false,
              use_launch_profile = true,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = parsed.args,
              configuration = parsed.configuration,
            })
          end
        )
      end,
      passthrough = true,
      subcommands = {
        default = {
          desc = "Debug the persisted default project with selected launch profile",
          handle = function(args, _)
            local parsed = parse_passthrough_args(args, "app")
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(
              function()
                client.workspace:debug({
                  use_default = true,
                  use_launch_profile = true,
                  file_path = vim.api.nvim_buf_get_name(0),
                  cli_args = parsed.args,
                  configuration = parsed.configuration,
                })
              end
            )
          end,
          passthrough = true,
        },
      },
    },
    attach = {
      desc = "Attach the debugger to a running .NET process",
      handle = function(_, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:debug_attach({}) end)
      end,
    },
  },
}

M.watch = {
  desc = "`dotnet watch --project <Picker> <DArgs>`",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "app")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:watch({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = parsed.args,
          configuration = parsed.configuration,
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      desc = "`dotnet watch --project <Picker Default> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "app")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:watch({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = parsed.args,
              configuration = parsed.configuration,
            })
          end
        )
      end,
      passthrough = true,
    },
  },
}

M.pack = {
  desc = "`dotnet pack -c release`",
  handle = function() actions.pack() end,
  passthrough = false,
}

M.push = {
  desc = "`dotnet pack` and push the package",
  handle = function() actions.pack_and_push() end,
  passthrough = false,
}

M.add = {
  subcommands = {
    package = {
      desc = "Pick a NuGet package and add it to a project",
      handle = function() require("easy-dotnet.nuget").add_package(nil, false) end,
      passthrough = true,
      subcommands = {
        prerelease = {
          desc = "Same as `add package`, including prerelease versions",
          passthrough = true,
          handle = function() require("easy-dotnet.nuget").add_package(nil, true) end,
        },
      },
    },
  },
}

M.remove = {
  subcommands = {
    package = {
      desc = "Pick a NuGet package and remove it from a project",
      handle = function() require("easy-dotnet.nuget").remove_nuget() end,
    },
  },
}

M.secrets = {
  desc = "Opens a picker for .NET user-secrets",
  handle = function(_, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.secrets:open() end)
  end,
}

M.test = {
  desc = "`dotnet test <Picker> <DArgs>`",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:test({ use_default = false, test_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
  subcommands = {
    default = {
      desc = "`dotnet test <Picker Default> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:test({ use_default = true, test_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
    },
    solution = {
      desc = "`dotnet test <sln> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:test_solution({ use_default = false, test_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
    },
    ["run-settings"] = {
      subcommands = {
        set = {
          desc = "Pick a `.runsettings` file for a project, applied when running tests through the VSTest adapter",
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.test:set_run_settings() end)
          end,
        },
      },
    },
  },
}

M.restore = {
  desc = "`dotnet restore <sln> <DArgs>`",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:restore({ restore_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
}

M.build = {
  desc = "`dotnet build <Picker> <DArgs>`",
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:build({ use_default = false, use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
  subcommands = {
    quickfix = {
      desc = "`dotnet build <Picker> <DArgs>` and opens build errors in the quickfix list",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = false, use_terminal = false, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
    },
    solution = {
      desc = "`dotnet build <sln> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build_solution({ use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          desc = "`dotnet build <sln> <DArgs>` and opens build errors in the quickfix list",
          handle = function(args, _)
            local parsed = parse_passthrough_args(args, "dotnet")
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.workspace:build_solution({ use_terminal = false, build_args = parsed.args, configuration = parsed.configuration }) end)
          end,
          passthrough = true,
        },
      },
    },
    default = {
      desc = "`dotnet build <Picker Default> <DArgs>`",
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = true, use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          desc = "`dotnet build <Picker Default> <DArgs>` and opens build errors in the quickfix list",
          handle = function(args, _)
            local parsed = parse_passthrough_args(args, "dotnet")
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.workspace:build({ use_default = true, use_terminal = false, build_args = parsed.args, configuration = parsed.configuration }) end)
          end,
          passthrough = true,
        },
      },
    },
  },
}

M.createfile = {
  desc = "Spawns a picker for creating a new file based on a `dotnet new` template",
  args = "<path>",
  passthrough = true,
  handle = function(args)
    local path = type(args) == "string" and args or args[1]
    require("easy-dotnet.actions.new").create_new_item(path)
  end,
}

M.testrunner = {
  desc = "Shows or hides the test runner",
  handle = function() require("easy-dotnet.test-runner").open() end,
}

M.outdated = {
  desc = "Shows the latest package versions as virtual text in `.csproj`, `.fsproj`, `Directory.Packages.props`, `Packages.props` and `Directory.Build.props` files",
  handle = function() require("easy-dotnet.outdated.outdated").outdated() end,
}

M.clean = {
  desc = "`dotnet clean <Picker>`",
  handle = function(_, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:clean() end)
  end,
  passthrough = false,
}

M.new = {
  desc = "Picker for creating a new project from a `dotnet new` template",
  handle = function() require("easy-dotnet.actions.new").new() end,
}

M.reset = {
  desc = "Deletes all files persisted by easy-dotnet.nvim. Use this if unable to pick a different solution or project",
  handle = function()
    local dir = require("easy-dotnet.constants").get_data_directory()
    vim.fs.rm(dir, { recursive = true, force = true })
    logger.info("Cached files deleted")
  end,
}

M.solution = {
  handle = nil,
  subcommands = {
    select = {
      desc = "Set the solution file for the current working directory, or pick one when no path is given. Useful when the solution is outside the normal search depth",
      args = "[path]",
      handle = function(args)
        local path = type(args) == "string" and args or (type(args) == "table" and args[1] or nil)
        if path then
          current_solution.set_solution(path)
          logger.info(string.format("Selected solution: %s", vim.fs.basename(path)))
          return
        end
        current_solution.pick_solution(function(picked)
          if not picked then return end
          current_solution.set_solution(picked)
          logger.info(string.format("Selected solution: %s", vim.fs.basename(picked)))
        end)
      end,
      passthrough = true,
    },
    add = {
      desc = "`dotnet sln <sln> add <Picker>`",
      handle = function()
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client:solution_add_project() end)
      end,
    },
    remove = {
      desc = "`dotnet sln <sln> remove <Picker>`",
      handle = function()
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client:solution_remove_project() end)
      end,
    },
  },
}

M.ef = {
  handle = nil,
  subcommands = {
    database = {
      handle = nil,
      subcommands = {
        update = {
          desc = "Updates the database to the latest migration",
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:database_update() end)
          end,
          subcommands = {
            pick = {
              desc = "Opens a picker to update the database to a selected migration",
              handle = function()
                local client = require("easy-dotnet.rpc.rpc").global_rpc_client
                client:initialize(function() client.entity_framework:migration_apply() end)
              end,
            },
          },
        },
        drop = {
          desc = "Drops the database for the selected project",
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:database_drop() end)
          end,
        },
      },
    },
    migrations = {
      handle = nil,
      subcommands = {
        add = {
          desc = "Adds a new Entity Framework migration with the specified name",
          args = "<name>",
          passthrough = true,
          handle = function(args)
            local migration_name = type(args) == "string" and args or args[1]
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:migration_add(migration_name) end)
          end,
        },
        remove = {
          desc = "Removes the last Entity Framework migration",
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:migration_remove() end)
          end,
        },
        list = {
          desc = "Lists all Entity Framework migrations",
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:migration_list() end)
          end,
        },
      },
    },
  },
}

M._server = {
  handle = nil,
  subcommands = {
    update = {
      desc = "Updates easy-dotnet-server (`dotnet tool install -g EasyDotnet`)",
      handle = function()
        local on_finished = job.register_job({ name = "Updating EasyDotnet", on_success_text = "Successfully updated", on_error_text = "Failed to update server" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:stop(function()
          local output = {}
          vim.fn.jobstart({ "dotnet", "tool", "install", "-g", "EasyDotnet" }, {
            on_stdout = function(_, data) vim.list_extend(output, data) end,
            on_stderr = function(_, data) vim.list_extend(output, data) end,
            on_exit = function(_, code)
              on_finished(code == 0)
              if code == 0 then
                local stdout = vim.trim(vim.fn.system("dotnet-easydotnet -v"):gsub("^Assembly", "Server"))
                vim.print(string.format("%s installed", stdout))
                vim.defer_fn(function()
                  require("easy-dotnet.rpc.rpc").global_rpc_client:initialize(function() end)
                end, 2000)
              else
                vim.print("Update failed, Code " .. code)
                vim.print(output)
              end
            end,
          })
        end)
      end,
    },
    stop = {
      desc = "Stops easy-dotnet-server",
      handle = function()
        local on_finished = job.register_job({ name = "Stopping server...", on_success_text = "Server stopped" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:stop(function() on_finished(true) end)
      end,
    },
    start = {
      desc = "Starts easy-dotnet-server",
      handle = function()
        local on_finished = job.register_job({ name = "Starting server...", on_success_text = "Server started" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:initialize(function() on_finished(true) end)
      end,
    },
    restart = {
      desc = "Restarts easy-dotnet-server",
      handle = function()
        local on_finished = job.register_job({ name = "Restarting server...", on_success_text = "Server restarted" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:restart(function() on_finished(true) end)
      end,
    },
    logdump = {
      desc = "Opens the easy-dotnet-server logs",
      handle = function() require("easy-dotnet.rpc.server").dump_logs() end,
      subcommands = {
        buildserver = {
          desc = "Opens the build server logs",
          handle = function() require("easy-dotnet.rpc.server").dump_buildserver_logs() end,
        },
        stdout = {
          desc = "Opens the easy-dotnet-server stdout",
          handle = function() require("easy-dotnet.rpc.server").dump_stdout_logs() end,
        },
      },
    },
    loglevel = {
      desc = "Sets the easy-dotnet-server log level (off, error, warning, information, verbose)",
      args = "<level>",
      passthrough = true,
      handle = function(args)
        local level = type(args) == "string" and args or (args and args[1])
        if not level or level == "" then
          vim.notify("Usage: Dotnet _server loglevel <off|error|warning|information|verbose>", vim.log.levels.WARN)
          return
        end
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function()
          client.server:server_set_log_level(level, function() vim.notify("Log level set to " .. level, vim.log.levels.INFO) end)
        end)
      end,
    },
  },
}

M.diagnostic = {
  desc = "Workspace diagnostics using the configured default severity",
  handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics() end,
  subcommands = {
    errors = {
      desc = "Workspace diagnostics, errors only",
      handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics("error") end,
    },
    warnings = {
      desc = "Workspace diagnostics, errors and warnings",
      handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics("warning") end,
    },
  },
}

M.terminal = {
  subcommands = {
    toggle = {
      desc = "Toggles the managed terminal panel",
      handle = function() require("easy-dotnet.terminal").toggle() end,
    },
    show = {
      desc = "Shows the managed terminal panel",
      handle = function() require("easy-dotnet.terminal").show() end,
    },
    hide = {
      desc = "Hides the managed terminal panel",
      handle = function() require("easy-dotnet.terminal").hide() end,
    },
  },
}

return M
