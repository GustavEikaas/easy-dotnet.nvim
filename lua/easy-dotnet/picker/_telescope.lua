local M = {}
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param title string | nil
---@return T
M.pick_sync = function(bufnr, options, title, autopick)
  local co = coroutine.running()
  local selected = nil
  M.picker(bufnr, options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick)
  if not selected then coroutine.yield() end
  return selected
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then autopick = true end
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end
  local picker = require("telescope.picker").new(bufnr, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({
      results = options,
      entry_maker = function(entry)
        return {
          display = entry.display,
          value = entry,
          ordinal = entry.display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr) require("telescope.actions").close(prompt_bufnr) end)
      return true
    end,
  })
  picker:find()
end

---@param bufnr number|nil
---@param options table
---@param on_select_cb function
---@param title string
---@param previewer function
M.preview_picker = function(bufnr, options, on_select_cb, title, previewer)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local previewers = require("telescope.previewers")
  local picker = require("telescope.picker").new(bufnr, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({
      results = options,
      entry_maker = function(entry)
        return {
          display = entry.display,
          value = entry,
          ordinal = entry.display,
        }
      end,
    }),
    previewer = previewers.new_buffer_previewer({
      title = title .. " preview",
      define_preview = previewer,
    }),
    sorter = conf.generic_sorter({}),
    preview = true,
    attach_mappings = function(_, map)
      map("i", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "<CR>", function(prompt_bufnr)
        local selection = require("telescope.actions.state").get_selected_entry()
        require("telescope.actions").close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr) require("telescope.actions").close(prompt_bufnr) end)
      return true
    end,
  })
  picker:find()
end

M.migration_picker = function(opts, migration)
  local picker = require("telescope.pickers").new(opts, {
    prompt_title = "Migrations",
    finder = require("telescope.finders").new_table({
      results = migration,
      entry_maker = opts.entry_maker,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer(opts),
  })
  picker:find()
end

M.nuget_search = function()
  local co = coroutine.running()
  local val
  local opts = {}
  require("telescope.pickers")
    .new(opts, {
      prompt_title = "Nuget search",
      finder = finders.new_async_job({
        --TODO: this part sucks I want to use JQ but it seems to be impossible to use it with telescope due to pipes and making OS independent
        command_generator = function(prompt) return { "dotnet", "package", "search", prompt or "", "--format", "json" } end,
        entry_maker = function(line)
          --HACK: ohgod.jpeg
          if line:find('"id":') == nil then return { valid = false } end
          local value = line:gsub('"id": "%s*([^"]+)%s*"', "%1"):match("^%s*(.-)%s*$"):gsub(",", "")
          return {
            value = value,
            ordinal = value,
            display = value,
          }
        end,
        cwd = vim.fn.getcwd(),
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function()
        actions.select_default:replace(function(prompt_bufnr)
          local selection = action_state.get_selected_entry(prompt_bufnr)
          actions.close(prompt_bufnr)
          val = selection.value
          coroutine.resume(co)
        end)
        return true
      end,
    })
    :find()
  coroutine.yield()
  return val
end

return M
