---@class easy-dotnet.RPC.Client.TemplateEngine
---@field _client easy-dotnet.RPC.StreamJsonRpc
---@field template_list fun(self: easy-dotnet.RPC.Client.TemplateEngine, cb?: fun(variables: easy-dotnet.Template.Template[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field template_parameters fun(self: easy-dotnet.RPC.Client.TemplateEngine, identity: string, cb?: fun(variables: easy-dotnet.Template.Parameter[]), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle
---@field template_instantiate fun(self: easy-dotnet.RPC.Client.TemplateEngine, identity: string, name: string, output_path: string, params: table<string,string>, cb?: fun(), opts?: easy-dotnet.RPC.CallOpts): easy-dotnet.RPC.CallHandle

---@type easy-dotnet.RPC.Client.TemplateEngine
local M = {}
M.__index = M

--- Constructor
---@param client easy-dotnet.RPC.StreamJsonRpc
---@return easy-dotnet.RPC.Client.TemplateEngine
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class easy-dotnet.Template.Template
---@field displayName string
---@field identity string
---@field type string|nil

function M:template_list(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    method = "template/list",
    params = {},
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

---@alias easy-dotnet.Template.ParameterDataType
---| '"text"'
---| '"bool"'
---| '"choice"'
---| '"string"'

---@class easy-dotnet.Template.Parameter
---@field name string
---@field defaultValue string|nil
---@field defaultIfOptionWithoutValue string|nil
---@field dataType easy-dotnet.Template.ParameterDataType
---@field description string|nil
---@field isRequired boolean
---@field choices table<string, string>|nil

function M:template_parameters(identity, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  return helper.create_enumerate_rpc_call({
    client = self._client,
    method = "template/parameters",
    params = { identity = identity },
    cb = cb,
    on_yield = nil,
    on_crash = opts.on_crash,
  })()
end

function M:template_instantiate(identity, name, output_path, params, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  if #vim.tbl_keys(params) == 0 then params["_"] = "" end

  return helper.create_rpc_call({
    client = self._client,
    job = nil,
    cb = cb,
    on_crash = opts.on_crash,
    method = "template/instantiate",
    params = { identity = identity, name = name, outputPath = output_path, parameters = params },
  })()
end

return M
