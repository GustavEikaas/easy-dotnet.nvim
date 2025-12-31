local apply_workspace_edit = require("easy-dotnet.roslyn.lsp.apply_workspace_edit")

---Group nested code actions into hierarchical groups.
---@return table<string, { leaf?: string, code_action: lsp.Command }[]>
local function get_grouped_code_actions(nested_code_actions)
  local grouped = {}

  for _, it in ipairs(nested_code_actions) do
    local path = it.data.CodeActionPath
    local fix_all_flavors = it.data.FixAllFlavors

    if #path == 1 then
      table.insert(grouped, {
        group = path[1],
        leaf = nil,
        code_action = it,
      })
    else
      local leaf = path[#path]
      local group = table.concat(path, " -> ", 2, #path - 1)

      if fix_all_flavors then leaf = "[Fix All] " .. leaf end

      grouped[group] = grouped[group] or {}
      table.insert(grouped[group], {
        leaf = leaf,
        code_action = it,
      })
    end
  end

  return grouped
end

---Resolve or apply a code action, including "Fix All" variants.
---
---@param client vim.lsp.Client
local function resolve_or_apply_code_action(client, action)
  if not action then return end

  if action.data and action.data.FixAllFlavors then
    local title = action.title or "Fix All"
    local options = action.data.FixAllFlavors
    require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(v) return { display = v, value = v } end, options), function(selected)
      if not selected then return end
      client:request("codeAction/resolveFixAll", {
        title = title,
        data = action.data,
        scope = selected.value,
      }, function(err, response)
        if err then
          vim.notify("Failed to apply code action")
          return
        end
        if response and response.edit then apply_workspace_edit(response.edit, client) end
      end)
    end, title, true, true)
  else
    client:request("codeAction/resolve", {
      title = action.title,
      data = action.data,
    }, function(err, response)
      if err then
        vim.notify("Failed to apply code action")
        return
      end
      if response and response.edit then apply_workspace_edit(response.edit, client) end
    end)
  end
end

---Entry point: handles Roslyn nested code actions.
---
---@param data lsp.Command              # The command arguments containing NestedCodeActions
---@param ctx easy-dotnet.Roslyn.CommandContext
---@return nil
return function(data, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if not client then return end

  local args = data.arguments[1]
  if not args then return end

  local grouped = get_grouped_code_actions(args.NestedCodeActions)

  local groups = vim.tbl_keys(grouped)
  require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(g) return { display = g, value = g } end, groups), function(group_selected)
    if not group_selected then return end

    local leaves = grouped[group_selected.value]

    if vim.islist(leaves) and #leaves == 1 and not leaves[1].leaf then
      local action = leaves[1].code_action
      resolve_or_apply_code_action(client, action)
      return
    end

    require("easy-dotnet.picker").picker(nil, vim.tbl_map(function(s) return { display = s.leaf, value = s } end, leaves), function(leaf_selected)
      if not leaf_selected then return end
      local action = leaf_selected.value.code_action
      resolve_or_apply_code_action(client, action)
    end, "Pick nested action", true, true)
  end, args.UniqueIdentifier or "Pick group", true, true)
end
