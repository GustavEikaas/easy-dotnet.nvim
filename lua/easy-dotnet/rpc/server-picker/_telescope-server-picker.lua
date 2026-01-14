local conf = require("telescope.config").values

---@type easy-dotnet.RPC.Picker
local M = {
  supports_auto_cancel_detection = true,
  pick = function(options, title, on_select, on_cancel)
    local picker = require("telescope.pickers").new({}, {
      prompt_title = title,
      finder = require("telescope.finders").new_table({
        results = options,
        entry_maker = function(entry)
          return {
            display = entry.display,
            value = entry.id,
            ordinal = entry.display,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(_, map)
        map("i", "<CR>", function(prompt_bufnr)
          local selection = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(prompt_bufnr)
          on_select(selection.value)
        end)
        map("n", "<CR>", function(prompt_bufnr)
          local selection = require("telescope.actions.state").get_selected_entry()
          require("telescope.actions").close(prompt_bufnr)
          on_select(selection.value)
        end)
        map("n", "q", function(prompt_bufnr) require("telescope.actions").close(prompt_bufnr) end)
        return true
      end,
    })
    picker:register_completion_callback(function() on_cancel() end)

    picker:find()
  end,
}

return M
