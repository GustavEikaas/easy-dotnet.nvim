local M = {}
local finders = require("telescope.finders")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values

M.nuget_search = function()
  local co = coroutine.running()
  local val
  local opts = {}
  require("telescope.pickers")
    .new(opts, {
      prompt_title = "Nuget search",
      finder = finders.new_async_job({
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

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param previewer function | nil
M.preview_picker = function(bufnr, options, on_select_cb, title, previewer)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local picker = require("telescope.pickers").new(bufnr, {
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

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param on_select_cb function
---@param title string | nil
---@param autopick boolean
---@param apply_numeration boolean
M.picker = function(bufnr, options, on_select_cb, title, autopick, apply_numeration)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local options_for_finder = {}
  for i, option in ipairs(options) do
    local display_text
    if apply_numeration then
      display_text = i .. ". " .. option.display
    else
      display_text = option.display
    end

    table.insert(options_for_finder, {
      display_text = display_text,
      option = option,
    })
  end

  local picker = require("telescope.pickers").new(bufnr, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({
      results = options_for_finder,
      entry_maker = function(entry)
        return {
          display = entry.display_text,
          value = entry.option,
          ordinal = entry.display_text,
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

M.multi_picker = function(options, on_select_cb, title, apply_numeration)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  local options_for_finder = {}
  for i, option in ipairs(options) do
    local display_text
    if apply_numeration then
      display_text = i .. ". " .. option.display
    else
      display_text = option.display
    end

    table.insert(options_for_finder, {
      display_text = display_text,
      option = option,
    })
  end

  local picker = require("telescope.pickers").new({}, {
    prompt_title = title,
    finder = require("telescope.finders").new_table({
      results = options_for_finder,
      entry_maker = function(entry)
        return {
          display = entry.display_text,
          value = entry.option,
          ordinal = entry.display_text,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(_, map)
      map("i", "<CR>", function(pb)
        local picker = action_state.get_current_picker(pb)
        local multi_selections = picker:get_multi_selection()

        actions.close(pb)

        if #multi_selections > 0 then
          local selected_values = {}
          for _, selection in ipairs(multi_selections) do
            table.insert(selected_values, selection.value)
          end
          on_select_cb(selected_values)
        else
          local selection = action_state.get_selected_entry()
          on_select_cb({ selection.value })
        end
      end)

      map("n", "<CR>", function(pb)
        local picker = action_state.get_current_picker(pb)
        local multi_selections = picker:get_multi_selection()

        actions.close(pb)

        if #multi_selections > 0 then
          local selected_values = {}
          for _, selection in ipairs(multi_selections) do
            table.insert(selected_values, selection.value)
          end
          on_select_cb(selected_values)
        else
          local selection = action_state.get_selected_entry()
          on_select_cb({ selection.value })
        end
      end)
      map("n", "q", function(prompt_bufnr) require("telescope.actions").close(prompt_bufnr) end)
      return true
    end,
  })
  picker:find()
end

---@generic T
---@param bufnr number | nil
---@param options table<T>
---@param title string | nil
---@param autopick boolean
---@param apply_numeration boolean
---@return T
M.pick_sync = function(bufnr, options, title, autopick, apply_numeration)
  local co = coroutine.running()
  local selected = nil
  M.picker(bufnr, options, function(i)
    selected = i
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick, apply_numeration)
  if not selected then coroutine.yield() end
  return selected
end

---@param params table picker/pick params from server
---@param response fun(result: table|nil)
M.server_picker = function(params, response)
  local rpc = require("easy-dotnet.rpc.rpc-client")

  local responded = false
  local function do_response(result)
    if responded then return end
    responded = true
    response(result)
  end

  local entries = {}
  for _, c in ipairs(params.choices) do
    table.insert(entries, { id = c.id, display = c.display })
  end

  local previewer_obj = nil
  if params.preview then
    previewer_obj = previewers.new_buffer_previewer({
      title = params.prompt .. " Preview",
      define_preview = function(self, entry, _status)
        local bufnr = self.state.bufnr
        local item_id = entry.value.id
        rpc.request("picker/preview", { guid = params.guid, itemId = item_id }, function(res)
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            local p = res.result
            if not p then return end
            if p.type == "File" then
              local ok, lines = pcall(vim.fn.readfile, p.path)
              if ok then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                local ft = vim.filetype.match({ filename = p.path }) or ""
                if ft ~= "" then vim.bo[bufnr].filetype = ft end
              end
            elseif p.type == "Text" then
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, p.lines or {})
              if p.filetype then vim.bo[bufnr].filetype = p.filetype end
            end
          end)
        end)
      end,
    })
  end

  local function handle_selection(prompt_bufnr)
    local curr_picker = action_state.get_current_picker(prompt_bufnr)
    local multi_sel = params.multi and curr_picker:get_multi_selection() or {}
    local single_sel = action_state.get_selected_entry()

    local ids = {}
    if #multi_sel > 0 then
      for _, s in ipairs(multi_sel) do
        table.insert(ids, s.value.id)
      end
    elseif single_sel then
      table.insert(ids, single_sel.value.id)
    end

    -- Respond before closing so BufUnload cancel is a no-op
    do_response(#ids > 0 and { selectedIds = ids } or nil)
    actions.close(prompt_bufnr)
  end

  local p = require("telescope.pickers").new({}, {
    prompt_title = (params.multi and "[Multi] " or "") .. params.prompt,
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry) return { display = entry.display, value = entry, ordinal = entry.display } end,
    }),
    previewer = previewer_obj,
    sorter = conf.generic_sorter({}),
    attach_mappings = function(_, map)
      actions.select_default:replace(handle_selection)
      map("n", "q", function(pb) actions.close(pb) end)
      if not params.multi then
        -- disable <Tab> toggle-selection so accidental tab doesn't mark entries
        map("i", "<Tab>", function() end)
        map("n", "<Tab>", function() end)
      end
      return true
    end,
  })
  p:find()

  if p.prompt_bufnr then vim.api.nvim_create_autocmd("BufUnload", {
    buffer = p.prompt_bufnr,
    once = true,
    callback = function() do_response(nil) end,
  }) end
end

return M
