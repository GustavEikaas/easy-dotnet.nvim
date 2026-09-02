local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
---@type table<string,easy-dotnet.Command>
local M = {}

---@class easy-dotnet.Command
---@field subcommands table<string,easy-dotnet.Command> | nil
---@field handle nil | fun(args: table<string>|string, options: table): nil
---@field passthrough boolean | nil

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
      handle = function(_, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:debug_attach({}) end)
      end,
    },
  },
}

M.watch = {
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
  handle = function() actions.pack() end,
  passthrough = false,
}

M.push = {
  handle = function() actions.pack_and_push() end,
  passthrough = false,
}

M.add = {
  subcommands = {
    package = {
      handle = function() require("easy-dotnet.nuget").add_package(nil, false) end,
      passthrough = true,
      subcommands = {
        prerelease = {
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
      handle = function() require("easy-dotnet.nuget").remove_nuget() end,
    },
  },
}

M.secrets = {
  handle = function(_, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.secrets:open() end)
  end,
}

M.test = {
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:test({ use_default = false, test_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:test({ use_default = true, test_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
    },
    solution = {
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
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:restore({ restore_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
}

M.build = {
  handle = function(args, _)
    local parsed = parse_passthrough_args(args, "dotnet")
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:build({ use_default = false, use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
  end,
  passthrough = true,
  subcommands = {
    quickfix = {
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = false, use_terminal = false, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
    },
    solution = {
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build_solution({ use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
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
      handle = function(args, _)
        local parsed = parse_passthrough_args(args, "dotnet")
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = true, use_terminal = true, build_args = parsed.args, configuration = parsed.configuration }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
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
  passthrough = true,
  handle = function(args)
    local path = type(args) == "string" and args or args[1]
    require("easy-dotnet.actions.new").create_new_item(path)
  end,
}

M.testrunner = {
  handle = function() require("easy-dotnet.test-runner").open() end,
}

M.project = {
  handle = nil,
  subcommands = {
    view = {
      handle = function() require("easy-dotnet.project-view").open() end,
    },
  },
}

M.outdated = {
  handle = function() require("easy-dotnet.outdated.outdated").outdated() end,
}

M.clean = {
  handle = function(_, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:clean() end)
  end,
  passthrough = false,
}

M.new = {
  handle = function() require("easy-dotnet.actions.new").new() end,
}

M.reset = {
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
      handle = function()
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client:solution_add_project() end)
      end,
    },
    remove = {
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
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:database_update() end)
          end,
          subcommands = {
            pick = {
              handle = function()
                local client = require("easy-dotnet.rpc.rpc").global_rpc_client
                client:initialize(function() client.entity_framework:migration_apply() end)
              end,
            },
          },
        },
        drop = {
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
          passthrough = true,
          handle = function(args)
            local migration_name = type(args) == "string" and args or args[1]
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:migration_add(migration_name) end)
          end,
        },
        remove = {
          handle = function()
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.entity_framework:migration_remove() end)
          end,
        },
        list = {
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
      handle = function()
        local on_finished = job.register_job({ name = "Stopping server...", on_success_text = "Server stopped" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:stop(function() on_finished(true) end)
      end,
    },
    start = {
      handle = function()
        local on_finished = job.register_job({ name = "Starting server...", on_success_text = "Server started" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:initialize(function() on_finished(true) end)
      end,
    },
    restart = {
      handle = function()
        local on_finished = job.register_job({ name = "Restarting server...", on_success_text = "Server restarted" })
        require("easy-dotnet.rpc.rpc").global_rpc_client:restart(function() on_finished(true) end)
      end,
    },
    logdump = {
      handle = function() require("easy-dotnet.rpc.server").dump_logs() end,
      subcommands = {
        buildserver = {
          handle = function() require("easy-dotnet.rpc.server").dump_buildserver_logs() end,
        },
        stdout = {
          handle = function() require("easy-dotnet.rpc.server").dump_stdout_logs() end,
        },
      },
    },
    loglevel = {
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
  handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics() end,
  subcommands = {
    errors = {
      handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics("error") end,
    },
    warnings = {
      handle = function() require("easy-dotnet.actions.diagnostics").get_workspace_diagnostics("warning") end,
    },
  },
}

M.terminal = {
  subcommands = {
    toggle = {
      handle = function() require("easy-dotnet.terminal").toggle() end,
    },
    show = {
      handle = function() require("easy-dotnet.terminal").show() end,
    },
    hide = {
      handle = function() require("easy-dotnet.terminal").hide() end,
    },
  },
}

return M
