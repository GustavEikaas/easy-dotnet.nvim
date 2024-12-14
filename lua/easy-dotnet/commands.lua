---@type table<string,Command>
local M = {}

---@class Command
---@field subcommands table<string,Command> | nil
---@field handle nil | fun(args: table<string>, options: table): nil
---@field passtrough boolean | nil

local function slice(array, start_index, end_index)
  local result = {}
  table.move(array, start_index, end_index, 1, result)
  return result
end

---@param arguments table<string>|nil
local function passthrough_dotnet_cli_args_handler(arguments)
  if not arguments or #arguments == 0 then
    return ""
  end
  local loweredArgument = arguments[1]:lower()
  if loweredArgument == "release" then
    return string.format("-c release %s", passthrough_dotnet_cli_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "debug" then
    return string.format("-c debug %s", passthrough_dotnet_cli_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "-c" then
    local flag = string.format("-c %s", #arguments >= 2 and arguments[2] or "")
    return string.format("%s %s", flag, passthrough_dotnet_cli_args_handler(slice(arguments, 3, #arguments) or ""))
  elseif loweredArgument == "--no-build" then
    return string.format("--no-build %s", passthrough_dotnet_cli_args_handler(slice(arguments, 2, #arguments) or ""))
  elseif loweredArgument == "--no-restore" then
    return string.format("--no-restore %s", passthrough_dotnet_cli_args_handler(slice(arguments, 2, #arguments) or ""))
  else
    vim.notify("Unknown argument to dotnet build " .. loweredArgument, vim.log.levels.WARN)
  end
end

local actions = require("easy-dotnet.actions")


---@type Command
M.run = {
  handle = function(args, options)
    actions.run(options.terminal, false, passthrough_dotnet_cli_args_handler(args))
  end,
  passtrough = true,
  subcommands = {
    default = {
      handle = function(_, options)
        actions.run(options.terminal, true, "")
      end
    },
    profile = {
      handle = function(_, options)
        actions.run_with_profile(options.terminal, false)
      end,
      subcommands = {
        default = {
          handle = function(_, options)
            actions.run_with_profile(options.terminal, true)
          end
        }
      }
    }
  }
}

M.secrets = {
  handle = function(_, options)
    local secrets = require("easy-dotnet.secrets")
    secrets.edit_secrets_picker(options.secrets.path)
  end,
}

M.test = {
  handle = function(args, options)
    actions.test(options.terminal, false, passthrough_dotnet_cli_args_handler(args))
  end,
  passtrough = true,
  subcommands = {
    default = {
      handle = function(_, options)
        actions.test(options.terminal, true)
      end
    },
    solution = {
      handle = function(_, options)
        actions.test_solution(options.terminal)
      end
    }
  }
}

M.restore = {
  handle = function(_, options)
    actions.restore(options.terminal)
  end
}

M.build = {
  handle = function(args, options)
    actions.build(options.terminal, false, passthrough_dotnet_cli_args_handler(args))
  end,
  passtrough = true,
  subcommands = {
    quickfix = {
      handle = function(args)
        actions.build_quickfix(false, passthrough_dotnet_cli_args_handler(args))
      end,
      passtrough = true
    },
    solution = {
      handle = function(_, options)
        --TODO: support additional args
        actions.build_solution(options.terminal)
      end
    },
    default = {
      handle = function(args, options)
        actions.build(options.terminal, true, passthrough_dotnet_cli_args_handler(args))
      end,
      passtrough = true,
      subcommands = {
        quickfix = {
          handle = function(args)
            actions.build_quickfix(true, passthrough_dotnet_cli_args_handler(args))
          end
        }
      }
    }
  }
}

M.createfile = {
  handle = function(args)
    require("easy-dotnet.actions.new").create_new_item(args[1])
  end
}

M.testrunner = {
  handle = function(_, options)
    require("easy-dotnet.test-runner.runner").runner(options.test_runner, options.get_sdk_path)
  end,
  subcommands = {
    refresh = {
      handle = function(_, options)
        require("easy-dotnet.test-runner.runner").refresh(options.test_runner, options.get_sdk_path(), { build = false })
      end,
      subcommands = {
        build = {
          handle = function(_, options)
            require("easy-dotnet.test-runner.runner").refresh(options.test_runner, options.get_sdk_path(),
              { build = true })
          end
        }
      }
    }
  }
}

M.outdated = {
  handle = function()
    require("easy-dotnet.outdated.outdated").outdated()
  end
}

M.clean = {
  handle = function()
    require("easy-dotnet.actions.clean").clean_solution()
  end
}

M.new = {
  handle = function()
    require("easy-dotnet.actions.new").new()
  end
}

M.reset = {
  handle = function()
    local dir = require("easy-dotnet.constants").get_data_directory()
    require("plenary.path"):new(dir):rm({ recursive = true })
    vim.notify("Cached files deleted")
  end
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
          if file then
            old = value
          end
        end

        local sln = require("easy-dotnet.parsers.sln-parse").find_solution_file(true)
        if sln == nil then
          print("No solutions found")
        end
        require("easy-dotnet.default-manager").set_default_solution(old, sln)
      end
    }
  }
}

M.ef = {
  handle = nil,
  subcommands = {
    database = {
      handle = nil,
      subcommands = {
        update = {
          handle = function()
            require("easy-dotnet.ef-core.database").database_update()
          end,
          subcommands = {
            pick = {
              handle = function()
                require("easy-dotnet.ef-core.database").database_update("pick")
              end
            }
          }
        },
        drop = {
          handle = function()
            require("easy-dotnet.ef-core.database").database_drop()
          end
        }
      }
    },
    migrations = {
      handle = nil,
      subcommands = {
        add = {
          passtrough = true,
          handle = function(args)
            require("easy-dotnet.ef-core.migration").add_migration(args[1])
          end
        },
        remove = {
          handle = function()
            require("easy-dotnet.ef-core.migration").remove_migration()
          end
        },
        list = {
          handle = function()
            require("easy-dotnet.ef-core.migration").list_migrations()
          end
        }
      }

    }
  }
}


return M
