local run_context = require("easy-dotnet.neotest.run-context")
local run_queue = require("easy-dotnet.neotest.run-queue")

---@param spec neotest.RunSpec
---@param _context table
---@return neotest.Process
return function(spec, _context)
  local client = require("easy-dotnet.rpc.rpc").global_rpc_client
  local ctx = run_context.begin_run(spec.context.node_id, spec.context.result_ids)

  run_queue.add(function()
    if spec.context.debug then
      client.testrunner:debug(spec.context.node_id, nil, "neotest")
    else
      client.testrunner:run(spec.context.node_id, nil, "neotest")
    end

    ctx.completion.wait()
  end)

  return {
    result = function() return ctx.completion.wait() end,
    output_stream = function() return ctx.result_chan.get end,
    output = function() return ctx:flush_stdout_to_tempfile() end,
    stop = function() client.testrunner:cancel() end,
    is_complete = function() return ctx.completion.is_set() end,
    attach = function() end,
  }
end
