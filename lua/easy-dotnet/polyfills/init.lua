--TODO: Remove this file once majority of users have migrated to >= 0.10.0
local M = {
  fs = {},
}

--- Return a list of all keys used in a table.
--- However, the order of the return table of keys is not guaranteed.
---
---@see From https://github.com/premake/premake-core/blob/master/src/base/table.lua
---
---@generic T
---@param t table<T, any> (table) Table
---@return T[] : List of keys
function M.tbl_keys(t)
  vim.validate({ t = { t, "t" } })
  --- @cast t table<any,any>

  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  return keys
end

function M.fs.joinpath(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end

--- Return a list of all values used in a table.
--- However, the order of the return table of values is not guaranteed.
---
---@generic T
---@param t table<any, T> (table) Table
---@return T[] : List of values
function M.tbl_values(t)
  vim.validate({ t = { t, "t" } })

  local values = {}
  for _, v in
    pairs(t --[[@as table<any,any>]])
  do
    table.insert(values, v)
  end
  return values
end

--- Apply a function to all values of a table.
---
---@generic T
---@param func fun(value: T): any Function
---@param t table<any, T> Table
---@return table : Table of transformed values
function M.tbl_map(func, t)
  vim.validate({ func = { func, "c" }, t = { t, "t" } })
  --- @cast t table<any,any>

  local rettab = {} --- @type table<any,any>
  for k, v in pairs(t) do
    rettab[k] = func(v)
  end
  return rettab
end

--- Filter a table using a predicate function
---
---@generic T
---@param func fun(value: T): boolean (function) Function
---@param t table<any, T> (table) Table
---@return T[] : Table of filtered values
function M.tbl_filter(func, t)
  vim.validate({ func = { func, "c" }, t = { t, "t" } })
  --- @cast t table<any,any>

  local rettab = {} --- @type table<any,any>
  for _, entry in pairs(t) do
    if func(entry) then rettab[#rettab + 1] = entry end
  end
  return rettab
end

--- @class M.tbl_contains.Opts
--- @inlinedoc
---
--- `value` is a function reference to be checked (default false)
--- @field predicate? boolean

--- Checks if a table contains a given value, specified either directly or via
--- a predicate that is checked for each value.
---
--- Example:
---
--- ```lua
--- M.tbl_contains({ 'a', { 'b', 'c' } }, function(v)
---   return M.deep_equal(v, { 'b', 'c' })
--- end, { predicate = true })
--- -- true
--- ```
---
---@see |M.list_contains()| for checking values in list-like tables
---
---@param t table Table to check
---@param value any Value to compare or predicate function reference
---@param opts? M.tbl_contains.Opts Keyword arguments |kwargs|:
---@return boolean `true` if `t` contains `value`
function M.tbl_contains(t, value, opts)
  vim.validate({ t = { t, "t" }, opts = { opts, "t", true } })
  --- @cast t table<any,any>

  local pred --- @type fun(v: any): boolean?
  if opts and opts.predicate then
    vim.validate({ value = { value, "c" } })
    pred = value
  else
    pred = function(v) return v == value end
  end

  for _, v in pairs(t) do
    if pred(v) then return true end
  end
  return false
end

--- Checks if a list-like table (integer keys without gaps) contains `value`.
---
---@see |M.tbl_contains()| for checking values in general tables
---
---@param t table Table to check (must be list-like, not validated)
---@param value any Value to compare
---@return boolean `true` if `t` contains `value`
function M.list_contains(t, value)
  vim.validate({ t = { t, "t" } })
  --- @cast t table<any,any>

  for _, v in ipairs(t) do
    if v == value then return true end
  end
  return false
end

M.iter = require("easy-dotnet.polyfills.iter")

return M
