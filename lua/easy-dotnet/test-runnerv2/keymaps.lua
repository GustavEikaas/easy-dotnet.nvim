return function()
  return {
    ["<CR>"] = {
      desc = "Toggle expand/collapse",
      handle = function(node, M)
        if node.children == nil or vim.tbl_isempty(node.children) then return end
        node.expanded = not node.expanded
        M.render()
      end,
    },
    ["h"] = {
      desc = "Collapse node",
      handle = function(node, M)
        if node.children then
          node.expanded = false
          M.render()
        end
      end,
    },
    ["l"] = {
      desc = "Expand node",
      handle = function(node, M)
        if node.children then
          node.expanded = true
          M.render()
        end
      end,
    },
  }
end
