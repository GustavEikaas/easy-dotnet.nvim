---@class TemplateEngineClient
---@field _client StreamJsonRpc
---@field template_list fun(self: TemplateEngineClient, cb?: fun(variables: DotnetNewTemplate[]), opts?: RPC_CallOpts): RPC_CallHandle
---@field template_parameters fun(self: TemplateEngineClient, identity: string, cb?: fun(variables: DotnetNewParameter[]), opts?: RPC_CallOpts): RPC_CallHandle
---@field template_instantiate fun(self: TemplateEngineClient, identity: string, name: string, output_path: string, params: table<string,string>, cb?: fun(), opts?: RPC_CallOpts): RPC_CallHandle

local M = {}
M.__index = M

--- Constructor
---@param client StreamJsonRpc
---@return TemplateEngineClient
function M.new(client)
  local self = setmetatable({}, M)
  self._client = client
  return self
end

---@class DotnetNewTemplate
---@field displayName string
---@field identity string
---@field type string|nil

function M:template_list(cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local id = self._client:request_enumerate("template/list", {}, nil, function(response) cb(response) end, helper.handle_rpc_error)
  return id
end

---@alias DotnetNewParameterDataType
---| '"text"'
---| '"bool"'
---| '"choice"'
---| '"string"'

---@class DotnetNewParameter
---@field name string
---@field defaultValue string|nil
---@field defaultIfOptionWithoutValue string|nil
---@field dataType DotnetNewParameterDataType
---@field description string|nil
---@field isRequired boolean
---@field choices table<string, string>|nil

function M:template_parameters(identity, cb, opts)
  local helper = require("easy-dotnet.rpc.dotnet-client")
  opts = opts or {}
  local id = self._client:request_enumerate("template/parameters", { identity = identity }, nil, function(response) cb(response) end, helper.handle_rpc_error)
  return id
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
