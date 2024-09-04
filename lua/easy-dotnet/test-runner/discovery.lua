local M = {}

local script_template = [[
//v1
#r "nuget: Microsoft.TestPlatform.TranslationLayer, 17.11.0"
#r "nuget: Microsoft.VisualStudio.TestPlatform, 14.0.0"
#r "nuget: MSTest.TestAdapter, 3.3.1"
#r "nuget: MSTest.TestFramework, 3.3.1"
#r "nuget: Newtonsoft.Json, 13.0.3"

open Microsoft.TestPlatform.VsTestConsole.TranslationLayer
open Microsoft.VisualStudio.TestPlatform.ObjectModel
open Microsoft.VisualStudio.TestPlatform.ObjectModel.Client
open System
open System.Collections.Generic
open System.IO
open Newtonsoft.Json

module TestDiscovery =

    type Test = { Id: Guid; Namespace: string; Name: string; FilePath: string; Linenumber: int }

    type PlaygroundTestDiscoveryHandler(outputFilePath: string) =
        interface ITestDiscoveryEventsHandler2 with
          member _.HandleDiscoveredTests(discoveredTestCases: IEnumerable<TestCase>) =
              let testCases = Seq.toList discoveredTestCases
              if testCases |> List.isEmpty |> not then
                  let tests = testCases |> List.map (fun s -> { Id = s.Id; Namespace = s.FullyQualifiedName; Name = s.DisplayName; FilePath = s.CodeFilePath; Linenumber = s.LineNumber })
                  use writer = new StreamWriter(outputFilePath, append = true)
                  for test in tests do
                    let json = JsonConvert.SerializeObject(test, Formatting.None).Replace("\n", "").Replace("\r", "")
                    writer.WriteLine(json)
              else
                  use writer = new StreamWriter(outputFilePath, append = true)
                  writer.WriteLine("[]")
          member _.HandleDiscoveryComplete(_: DiscoveryCompleteEventArgs, _: IEnumerable<TestCase>): unit =
              ()
          member _.HandleLogMessage(_: Logging.TestMessageLevel, _: string): unit =
              ()
          member _.HandleRawMessage(_: string): unit =
              ()


    type TestSessionHandler() =
      let mutable testSessionInfo: TestSessionInfo option = None

      interface ITestSessionEventsHandler with
        member _.HandleStartTestSessionComplete(eventArgs: StartTestSessionCompleteEventArgs) =
            testSessionInfo <- Some(eventArgs.TestSessionInfo)
        member _.HandleLogMessage(_: Logging.TestMessageLevel, _: string): unit =
            ()
        member _.HandleRawMessage(_: string): unit =
            ()
        member _.HandleStopTestSessionComplete(_: StopTestSessionCompleteEventArgs): unit =
            ()

      member _.TestSessionInfo
        with get() = testSessionInfo
        and set(value) = testSessionInfo <- value

    let main(argv: string[]) =
      if argv.Length <> 3 then
        printfn "Usage: fsi script.fsx <vstest-console-path> <test-dll-path> <output-file-path>"
        1
      else
        let console = argv.[0]

        let sourceSettings = """
            <RunSettings>
            </RunSettings>
            """

        let sources = argv.[1..1]
        let outputFilePath = argv.[2]

        let environmentVariables = Dictionary<string, string>()
        environmentVariables.Add("VSTEST_CONNECTION_TIMEOUT", "999")
        environmentVariables.Add("VSTEST_DEBUG_NOBP", "1")
        environmentVariables.Add("VSTEST_RUNNER_DEBUG_ATTACHVS", "0")
        environmentVariables.Add("VSTEST_HOST_DEBUG_ATTACHVS", "0")
        environmentVariables.Add("VSTEST_DATACOLLECTOR_DEBUG_ATTACHVS", "0")

        let options = TestPlatformOptions(CollectMetrics = true)

        let r = VsTestConsoleWrapper(console, ConsoleParameters(EnvironmentVariables = environmentVariables))
        let sessionHandler = TestSessionHandler()
        let discoveryHandler = PlaygroundTestDiscoveryHandler(outputFilePath)
        let testSession =
          match sessionHandler.TestSessionInfo with
          | Some info -> info
          | None ->
              new TestSessionInfo()

        r.DiscoverTests(sources, sourceSettings, options, testSession, discoveryHandler)
        0

    main fsi.CommandLineArgs.[1..]
]]

local script_name = "test_discovery.fsx"

---@param file file*
---@param filepath string
local function check_and_upgrade_script(file, filepath)
  local v = file:read("l"):match("//v(%d+)")
  file:close()
  local new_v = script_template:match("//v(%d+)")
  if v ~= new_v then
    local overwrite_file = io.open(filepath, "w+")
    if overwrite_file == nil then
      error("Failed to create the file: " .. filepath)
    end
    vim.notify("Updating " .. script_name, vim.log.levels.INFO)
    overwrite_file:write(script_template)
    overwrite_file:close()
  end
end

---@return string
local ensure_and_get_fsx_path = function()
  local file_template = script_template
  local dir = require("easy-dotnet.constants").get_data_directory()
  local filepath = vim.fs.joinpath(dir, script_name)
  local file = io.open(filepath, "r")
  if file then
    check_and_upgrade_script(file, filepath)
  else
    file = io.open(filepath, "w")
    if file == nil then
      error("Failed to create the file: " .. filepath)
    end
    file:write(file_template)

    file:close()
  end

  return filepath
end

M.get_script_path = ensure_and_get_fsx_path

return M
