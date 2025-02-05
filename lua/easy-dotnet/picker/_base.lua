local M = {}

M.nuget_search = function()
  local Job = require("plenary.job")
  local co = coroutine.running()
  local val
  local function search_nuget(prompt)
    local results = {}
    Job:new({
      command = "dotnet",
      args = { "package", "search", prompt or "", "--format", "json" },
      cwd = vim.fn.getcwd(),
      on_stdout = function(_, line)
        if line:find('"id":') then
          local value = line:gsub('"id": "%s*([^"]+)%s*"', "%1"):match("^%s*(.-)%s*$"):gsub(",", "")
          table.insert(results, { display = value, value = value })
        end
      end,
      on_exit = function()
        vim.schedule(function()
          local items = {}
          for _, result in ipairs(results) do
            table.insert(items, result.display)
          end
          vim.ui.select(items, { prompt = "Nuget search" }, function(choice)
            if choice then
              for _, result in ipairs(results) do
                if result.display == choice then
                  val = result.value
                  coroutine.resume(co)
                  return
                end
              end
            else
              coroutine.resume(co)
            end
          end)
        end)
      end,
    }):start()
  end

  local function prompt_for_search()
    vim.ui.input({ prompt = "Enter search query: " }, function(input)
      if input then
        search_nuget(input)
      else
        coroutine.resume(co)
      end
    end)
  end
  prompt_for_search()
  coroutine.yield()
  return val
end

M.migration_pick = function(opts, migration)
  vim.ui.select(migration, {
    prompt = "Migrations",
    format_item = function(item) return opts.entry_maker(item).display end,
  }, function(choice)
    if choice then opts.on_select(choice) end
  end)
end

M.preview_picker = function(bufnr, options, on_select_cb, title, previewer)
  if #options == 0 then error("No options provided, minimum 1 is required") end

  -- Auto pick if only one option present
  if #options == 1 then
    on_select_cb(options[1])
    return
  end

  local entries = {}
  for _, option in ipairs(options) do
    table.insert(entries, option.display)
  end

  vim.ui.select(entries, { prompt = title }, function(selected)
    if selected then
      for _, option in ipairs(options) do
        if option.display == selected then
          on_select_cb(option)
          break
        end
      end
    end
  end)
end

M.picker = function(bufnr, options, on_select_cb, title, autopick)
  if autopick == nil then autopick = true end
  if #options == 0 then error("No options provided, minimum 1 is required") end
  -- Auto pick if only one option present
  if #options == 1 and autopick == true then
    on_select_cb(options[1])
    return
  end

  local items = {}
  for _, option in ipairs(options) do
    table.insert(items, option.display)
  end

  vim.ui.select(items, { prompt = title }, function(choice)
    if choice then
      for _, option in ipairs(options) do
        if option.display == choice then
          on_select_cb(option)
          break
        end
      end
    end
  end)
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
    if coroutine.status(co) ~= "running" then coroutine.resume(co) end
  end, title or "", autopick)
  if not selected then coroutine.yield() end
  return selected
end

return M
