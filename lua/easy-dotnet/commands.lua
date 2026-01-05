local job = require("easy-dotnet.ui-modules.jobs")
local logger = require("easy-dotnet.logger")
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
  handle = function(args, options) actions.run(options.terminal, false, passthrough_dotnet_cli_args_handler(args)) end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, options) actions.run(options.terminal, true, passthrough_dotnet_cli_args_handler(args)) end,
      passthrough = true,
    },
    profile = {
      handle = function(args, options) actions.run_with_profile(options.terminal, false, passthrough_dotnet_cli_args_handler(args)) end,
      passthrough = true,
      subcommands = {
        default = {
          handle = function(args, options) actions.run_with_profile(options.terminal, true, passthrough_dotnet_cli_args_handler(args)) end,
          passthrough = true,
        },
      },
    },
  },
}

M.debug = {
  handle = function(args, options) actions.run(options.terminal, false, passthrough_dotnet_cli_args_handler(args), true) end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, options) actions.run(options.terminal, true, passthrough_dotnet_cli_args_handler(args), true) end,
      passthrough = true,
    },
    watch = {
      handle = function()
        local client = require("easy-dotnet.rpc.rpc").global_rpc_client
        client:initialize(function() client.msbuild:msbuild_watch({ targetPath = [[C:\Users\gusta\repo\easy-dotnet-server-test\EasyDotnet.IDE\EasyDotnet.IDE.csproj]], configuration = "Debug" }) end)
      end,
    },
    profile = {
      handle = function(args, options) actions.run_with_profile(options.terminal, false, passthrough_dotnet_cli_args_handler(args), true) end,
      passthrough = true,
      subcommands = {
        default = {
          handle = function(args, options) actions.run_with_profile(options.terminal, true, passthrough_dotnet_cli_args_handler(args), true) end,
          passthrough = true,
        },
      },
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
  handle = function(args, options) actions.watch(options.terminal, false, passthrough_dotnet_cli_args_handler(args)) end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, options) actions.watch(options.terminal, true, passthrough_dotnet_cli_args_handler(args)) end,
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
      handle = function() require("easy-dotnet.nuget").search_nuget(nil, false) end,
      passthrough = true,
      subcommands = {
        prerelease = {
          passthrough = true,
          handle = function() require("easy-dotnet.nuget").search_nuget(nil, true) end,
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
  handle = function(args, options) actions.test(options.terminal, false, passthrough_dotnet_cli_args_handler(args)) end,
  passthrough = true,
  subcommands = {
    default = {
      handle = function(args, options) actions.test(options.terminal, true, passthrough_dotnet_cli_args_handler(args)) end,
      passthrough = true,
    },
    solution = {
      handle = function(args, options) actions.test_solution(options.terminal, passthrough_dotnet_cli_args_handler(args)) end,
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
  handle = function(args, options) actions.restore(options.terminal, stringify_args(args)) end,
  passthrough = true,
}

M.build = {
  handle = function(args, options)
    local terminal = options and options.terminal or nil
    actions.build(terminal, false, passthrough_dotnet_cli_args_handler(args))
  end,
  passthrough = true,
  subcommands = {
    quickfix = {
      handle = function(args) actions.build_quickfix(false, passthrough_dotnet_cli_args_handler(args)) end,
      passthrough = true,
    },
    solution = {
      handle = function(args, options)
        local terminal = options and options.terminal or nil
        actions.build_solution(terminal, passthrough_dotnet_cli_args_handler(args))
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          handle = function(args) actions.build_solution_quickfix(passthrough_dotnet_cli_args_handler(args)) end,
          passthrough = true,
        },
      },
    },
    default = {
      handle = function(args, options)
        local terminal = options and options.terminal or nil
        actions.build(terminal, true, passthrough_dotnet_cli_args_handler(args))
      end,
      passthrough = true,
      subcommands = {
        quickfix = {
          handle = function(args) actions.build_quickfix(true, passthrough_dotnet_cli_args_handler(args)) end,
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
  handle = function(_, options)
    local test_runner = options and options.test_runner or nil
    require("easy-dotnet.test-runner.runner").runner(test_runner)
  end,
  subcommands = {
    refresh = {
      handle = function(_, options)
        local test_runner = options and options.test_runner or nil
        require("easy-dotnet.test-runner.runner").refresh(test_runner)
      end,
      subcommands = {
        ---@deprecated building happens automatically now
        build = {
          handle = function(_, options)
            local test_runner = options and options.test_runner or nil
            require("easy-dotnet.test-runner.runner").refresh(test_runner)
          end,
        },
      },
    },
  },
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
      handle = function()
        local files = require("easy-dotnet.parsers.sln-parse").get_solutions()
        local old = nil
        for _, value in ipairs(files) do
          local file = require("easy-dotnet.default-manager").try_get_cache_file(value)
          if file then old = value end
        end

        local sln = require("easy-dotnet.parsers.sln-parse").find_solution_file(true)
        if sln == nil then print("No solutions found") end
        require("easy-dotnet.default-manager").set_default_solution(old, sln)
      end,
    },
    add = {
      handle = function()
        local sln_file = require("easy-dotnet.parsers.sln-parse").find_solution_file()
        assert(type(sln_file) == "string")
        require("easy-dotnet.parsers.sln-parse").add_project_to_solution(sln_file)
      end,
    },
    remove = {
      handle = function()
        local sln_file = require("easy-dotnet.parsers.sln-parse").find_solution_file()
        assert(type(sln_file) == "string")
        require("easy-dotnet.parsers.sln-parse").remove_project_from_solution(sln_file)
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
          handle = function() require("easy-dotnet.ef-core.database").database_update() end,
          subcommands = {
            pick = {
              handle = function() require("easy-dotnet.ef-core.database").database_update("pick") end,
            },
          },
        },
        drop = {
          handle = function() require("easy-dotnet.ef-core.database").database_drop() end,
        },
      },
    },
    migrations = {
      handle = nil,
      subcommands = {
        add = {
          passthrough = true,
          handle = function(args) require("easy-dotnet.ef-core.migration").add_migration(args[1]) end,
        },
        remove = {
          handle = function() require("easy-dotnet.ef-core.migration").remove_migration() end,
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

return M
