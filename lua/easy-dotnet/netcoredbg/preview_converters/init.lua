local M = {}

---@class easy-dotnet.Debugger.PreviewConverter
---@field satisfies_type fun(var_type: string|nil, response: table): boolean
---@field convert fun(result: string, response: table): string|{ text: string, filetype?: string, title?: string }

---@type easy-dotnet.Debugger.PreviewConverter[]
M.preview_converters = {}

---@param converter easy-dotnet.Debugger.PreviewConverter
function M.register(converter)
  table.insert(M.preview_converters, converter)
end

---@param converters easy-dotnet.Debugger.PreviewConverter[]|nil
function M.set(converters)
  M.preview_converters = {}
  for _, converter in ipairs(converters or {}) do
    M.register(converter)
  end
end

---@param result string
---@param response table
---@return { text: string, filetype?: string, title?: string }
function M.convert(result, response)
  local var_type = response and response.type or nil
  local matches = vim
    .iter(M.preview_converters)
    :filter(function(r) return r.satisfies_type(var_type, response) end)
    :totable()

  if #matches > 1 then
    error("More than one preview converter found for type " .. tostring(var_type))
  elseif #matches == 1 then
    local converted = matches[1].convert(result, response)
    if type(converted) == "table" then
      return {
        text = converted.text or result,
        filetype = converted.filetype,
        title = converted.title,
      }
    end

    return { text = tostring(converted) }
  end

  return { text = result }
end

return M
