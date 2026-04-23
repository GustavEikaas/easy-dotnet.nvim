local run_context = require("easy-dotnet.neotest.run-context")

---@param spec neotest.RunSpec
---@param _context table
---@return neotest.Process
return function(spec, _context)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local ctx = run_context.begin_run(spec.context.node_id, spec.context.result_ids)

  if spec.context.debug then
    client.testrunner:debug(spec.context.node_id, nil, "neotest")
  else
    client.testrunner:run(spec.context.node_id, nil, "neotest")
  end

  return {
    result = function() return ctx.completion.wait() end,
    output_stream = function() return ctx.result_chan.get end,
    output = function() return ctx:flush_stdout_to_tempfile() end,
    stop = function() client.testrunner:cancel() end,
    is_complete = function() return ctx.done end,
    attach = function() end,
  }
end
