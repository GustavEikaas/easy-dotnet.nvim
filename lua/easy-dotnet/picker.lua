local M = {}

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then
    autopick = true
  end
  if (#options == 0) then
    error("No options provided, minimum 1 is required")
  end

  -- Auto pick if only one option present
  if (#options == 1 and autopick == true) then
    on_select_cb(options[1])
    return
  end
  local picker = require('telescope.pickers').new(bufnr, {
    prompt_title = title,
    finder = require('telescope.finders').new_table {
      results = options,
      entry_maker = function(entry)
        return {
          display = entry.display,
          value = entry,
          ordinal = entry.display,
        }
      end,
    },
    sorter = require('telescope.config').values.generic_sorter({}),
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map('n', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr)
        require("telescope.actions").close(prompt_bufnr)
      end)
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
  if (#options == 0) then
    error("No options provided, minimum 1 is required")
  end

  -- Auto pick if only one option present
  if (#options == 1) then
    on_select_cb(options[1])
    return
  end

  local previewers = require("telescope.previewers")
  local picker = require('telescope.pickers').new(bufnr, {
    prompt_title = title,
    finder = require('telescope.finders').new_table {
      results = options,
      entry_maker = function(entry)
        return {
          display = entry.display,
          value = entry,
          ordinal = entry.display,
        }
      end,
    },
    previewer = previewers.new_buffer_previewer {
      title = title .. " preview",
      define_preview = previewer
    },
    sorter = require('telescope.config').values.generic_sorter({}),
    preview = true,
    attach_mappings = function(_, map)
      map('i', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map('n', '<CR>', function(prompt_bufnr)
        local selection = require('telescope.actions.state').get_selected_entry()
        require('telescope.actions').close(prompt_bufnr)
        on_select_cb(selection.value)
      end)
      map("n", "q", function(prompt_bufnr)
        require("telescope.actions").close(prompt_bufnr)
      end)
      return true
    end,
  })
  picker:find()
end

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
    if coroutine.status(co) ~= "running" then
      coroutine.resume(co)
    end
  end, title or "", autopick)
  if not selected then
    coroutine.yield()
  end
  return selected
end


return M
