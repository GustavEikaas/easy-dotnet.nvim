local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
local current_solution = require("easy-dotnet.current_solution")
---@type table<string,easy-dotnet.Command>
local M = {}

---@class easy-dotnet.Command
---@field subcommands table<string,easy-dotnet.Command> | nil
---@field handle nil | fun(args: table<string>|string, options: table): nil
---@field passthrough boolean | nil

---@param arguments table<string>| nil | string
local function passthrough_dotnet_cli_args_handler(arguments)
  if not arguments or #arguments == 0 then return "" end

  if type(arguments) == "string" then return arguments end

  local loweredArgument = arguments[1]:lower()
  -- Shorthand dotnet build release -> dotnet build -c release
  if loweredArgument == "release" then
    return string.format("-c release %s", passthrough_dotnet_cli_args_handler(vim.list_slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "debug" then
    return string.format("-c debug %s", passthrough_dotnet_cli_args_handler(vim.list_slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "-c" or loweredArgument == "--configuration" then
    return string.format("%s %s %s", loweredArgument, (#arguments >= 2 and arguments[2] or ""), passthrough_dotnet_cli_args_handler(vim.list_slice(arguments, 3, #arguments) or ""))
  end

  return string.format("%s %s", loweredArgument, passthrough_dotnet_cli_args_handler(vim.list_slice(arguments, 2, #arguments)))
end

---@param args string | string[] | nil
---@return string
local function stringify_args(args)
  ---@type string
  return type(args) == "table" and table.concat(args, " ") or args or ""
end

local actions = require("easy-dotnet.actions")

---This entire object is exposed, any change to this will possibly be a breaking change, tread carefully
---@type easy-dotnet.Command
M.run = {
  handle = function(args, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:run({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = passthrough_dotnet_cli_args_handler(args),
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:run({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = passthrough_dotnet_cli_args_handler(args),
            })
          end
        )
      end,
      passthrough = true,
    },
    profile = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:run({
              use_default = false,
              use_launch_profile = true,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = passthrough_dotnet_cli_args_handler(args),
            })
          end
        )
      end,
      passthrough = true,
      subcommands = {
        default = {
          handle = function(args, _)
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(
              function()
                client.workspace:run({
                  use_default = true,
                  use_launch_profile = true,
                  file_path = vim.api.nvim_buf_get_name(0),
                  cli_args = passthrough_dotnet_cli_args_handler(args),
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
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:debug({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = passthrough_dotnet_cli_args_handler(args),
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:debug({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = passthrough_dotnet_cli_args_handler(args),
            })
          end
        )
      end,
      passthrough = true,
    },
    profile = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:debug({
              use_default = false,
              use_launch_profile = true,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = passthrough_dotnet_cli_args_handler(args),
            })
          end
        )
      end,
      passthrough = true,
      subcommands = {
        default = {
          handle = function(args, _)
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(
              function()
                client.workspace:debug({
                  use_default = true,
                  use_launch_profile = true,
                  file_path = vim.api.nvim_buf_get_name(0),
                  cli_args = passthrough_dotnet_cli_args_handler(args),
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

M._cached_files = {
  handle = function()
    local dir = require("easy-dotnet.constants").get_data_directory()
    local pattern = dir .. [[/*.json]]
    local files = vim.tbl_map(function(value) return { display = vim.fs.basename(value), name = value, path = value } end, vim.fn.glob(pattern, false, true))
    local file_preview = function(self, entry)
      local path = entry.value.path
      local content = table.concat(vim.fn.readfile(path), "\n")

      local ok, parsed = pcall(vim.json.decode, content)
      if not ok then
        vim.notify("Invalid JSON in: " .. path, vim.log.levels.ERROR)
        return
      end

      local lines = vim.split(vim.inspect(parsed), "\n")
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
    end

    require("easy-dotnet.picker").preview_picker(nil, files, function(i) vim.cmd("edit " .. i.path) end, "", file_preview)
  end,
}

M.watch = {
  handle = function(args, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(
      function()
        client.workspace:watch({
          use_default = false,
          use_launch_profile = false,
          file_path = vim.api.nvim_buf_get_name(0),
          cli_args = passthrough_dotnet_cli_args_handler(args),
        })
      end
    )
  end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(
          function()
            client.workspace:watch({
              use_default = true,
              use_launch_profile = false,
              file_path = vim.api.nvim_buf_get_name(0),
              cli_args = passthrough_dotnet_cli_args_handler(args),
            })
          end
        )
      end,
      passthrough = true,
    },
  },
}

M.project = {
  subcommands = {
    view = {
      handle = function() require("easy-dotnet.project-view").open_or_toggle() end,
      subcommands = {
        default = {
          handle = function() require("easy-dotnet.project-view").open_or_toggle_default() end,
        },
      },
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
  handle = function(_, options)
    local secrets = require("easy-dotnet.secrets")
    secrets.edit_secrets_picker(options.secrets.path)
  end,
}

M.test = {
  handle = function(args, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:test({ use_default = false, test_args = passthrough_dotnet_cli_args_handler(args) }) end)
  end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:test({ use_default = true, test_args = passthrough_dotnet_cli_args_handler(args) }) end)
      end,
      passthrough = true,
    },
    solution = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:test_solution({ use_default = false, test_args = passthrough_dotnet_cli_args_handler(args) }) end)
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
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:restore({ restore_args = passthrough_dotnet_cli_args_handler(args) }) end)
  end,
  passthrough = true,
}

M.build = {
  handle = function(args, _)
    local client = require("easy-dotnet.rpc.rpc").global_rpc_client
    client:initialize(function() client.workspace:build({ use_default = false, use_terminal = true, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
  end,
  passthrough = true,
  subcommands = {
    quickfix = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = false, use_terminal = false, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
      end,
      passthrough = true,
    },
    solution = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build_solution({ use_terminal = true, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          handle = function(args, _)
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.workspace:build_solution({ use_terminal = false, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
          end,
          passthrough = true,
        },
      },
    },
    default = {
      handle = function(args, _)
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.workspace:build({ use_default = true, use_terminal = true, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          handle = function(args, _)
            local client = require("easy-dotnet.rpc.rpc").global_rpc_client
            client:initialize(function() client.workspace:build({ use_default = true, use_terminal = false, build_args = passthrough_dotnet_cli_args_handler(args) }) end)
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

M.outdated = {
  handle = function() require("easy-dotnet.outdated.outdated").outdated() end,
}

M.clean = {
  handle = function(args) require("easy-dotnet.actions.clean").clean_solution(stringify_args(args)) end,
  passthrough = true,
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
        local path = type(args) == "string" and args or args[1]
        current_solution.set_solution(path)
        logger.info(string.format("Selected solution: %s", vim.fs.basename(path)))
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
          handle = function() require("easy-dotnet.ef-core.migration").list_migrations() end,
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

M.lsp = {
  subcommands = {
    start = {
      handle = function() require("easy-dotnet.roslyn.lsp").start() end,
    },
    restart = {
      handle = function() require("easy-dotnet.roslyn.lsp").restart() end,
    },
    stop = {
      handle = function() require("easy-dotnet.roslyn.lsp").stop() end,
    },
  },

}

M.generatetest = {
  handle = function() require("easy-dotnet.actions.generate-test").generate_test() end,
}



return M
