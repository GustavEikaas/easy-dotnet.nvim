---@class easy-dotnet.Roslyn.RangePosition
---@field line number
---@field character number

---@class easy-dotnet.Roslyn.TextDocument
---@field uri string

---@class easy-dotnet.TestRunner.Argument
---@field attachDebugger boolean
---@field range { start: RangePosition, ["end"]: RangePosition }
---@field textDocument easy-dotnet.Roslyn.TextDocument

---@class easy-dotnet.TestRunner.Command
---@field arguments easy-dotnet.TestRunner.Argument[]
---@field command string
---@field title string

---@param command easy-dotnet.TestRunner.Command
---@param ctx easy-dotnet.Roslyn.CommandContext
return function(command, ctx)
  local arg = command.arguments[1] -- usually only one
  local _ = ctx.client_id
  local file_uri = arg.textDocument.uri
  local fname = vim.uri_to_fname(file_uri)

  local range = {
    start = {
      line = arg.range.start.line, -- LSP is 0-indexed, Vim is 1-indexed
      character = arg.range.start.character,
    },
    ["end"] = {
      line = arg.range["end"].line,
      character = arg.range["end"].character,
    },
  }

  local _ = {
    file = fname,
    range = range,
  }

  --TODO: send request to easy-dotnet-server
end
