local M = {}

local file_template = [[
//v1
#r "nuget: Newtonsoft.Json"

open System
open System.IO
open System.Xml
open Newtonsoft.Json.Linq
open Newtonsoft.Json

let xmlToJson (xml: string) : JObject =
    // Load the XML string into an XmlDocument
    let xmlDoc = new XmlDocument()
    xmlDoc.LoadXml(xml)
    // Convert the XmlDocument to JSON and parse it into a JObject
    let jsonString = JsonConvert.SerializeXmlNode(xmlDoc, Newtonsoft.Json.Formatting.Indented)
    JObject.Parse(jsonString)

let extractResults (jsonObj: JObject) : JObject option =
    // Extract the "Results" object from the JSON object
    jsonObj.SelectToken("$.TestRun.Results") :?> JObject |> Option.ofObj

let main (argv: string[]) =
    if argv.Length <> 1 then
        printfn "Usage: fsi script.fsx <xml-file-path>"
        1
    else
        try
            let filePath = argv.[0]
            if File.Exists(filePath) then
                let xmlContent = File.ReadAllText(filePath)
                let jsonObj = xmlToJson(xmlContent)
                match extractResults(jsonObj) with
                | Some results ->
                    printfn "%s" (results.ToString(Formatting.Indented))
                    0
                | None ->
                    printfn "Error: 'Results' object not found in the JSON output."
                    1
            else
                printfn "Error: File not found - %s" filePath
                1
        with
        | :? System.Exception as ex ->
            printfn "Error: %s" ex.Message
            1

main fsi.CommandLineArgs.[1..]
]]

local ensure_and_get_fsx_path = function()
  local dir = vim.fs.joinpath(vim.fn.stdpath("data"), "easy-dotnet")
  local file_utils = require("easy-dotnet.file-utils")
  file_utils.ensure_directory_exists(dir)
  local filepath = vim.fs.joinpath(dir, "test_parser.fsx")
  local file = io.open(filepath, "r")
  if file then
    file:close()
  else
    file = io.open(filepath, "w")
    if file == nil then
      print("Failed to create the file: " .. filepath)
      return
    end
    file:write(file_template)

    file:close()
  end

  return filepath
end

--- @class TestResult
--- @field UnitTestResult TestCase[]

--- @class TestCase
--- @field ["@executionId"] string
--- @field ["@testId"] string
--- @field ["@testName"] string
--- @field ["@computerName"] string
--- @field ["@duration"] string
--- @field ["@startTime"] string
--- @field ["@endTime"] string
--- @field ["@testType"] string
--- @field ["@outcome"] string
--- @field ["@testListId"] string
--- @field ["@relativeResultsDirectory"] string
--- @field Output Output

--- @class Output
--- @field ErrorInfo? ErrorInfo
--- @field StdOut? string

--- @class ErrorInfo
--- @field Message string
--- @field StackTrace string

---@param xml_path string
M.xml_to_json = function(xml_path, cb)
  local fsx_file = ensure_and_get_fsx_path()
  local command = string.format("dotnet fsi %s '%s'", fsx_file, xml_path)


  vim.fn.jobstart(command, {
    stdout_buffered = true,
    ---@param data string[]
    on_stdout = function(_, data)
      local output = table.concat(data)
      local pos = output:find("{")

      if pos == nil then
        require("easy-dotnet.debug").write_to_log(output)
        error("Invalid json returned from fsx script")
      end

      ---@type TestResult
      local test_summary = vim.fn.json_decode(output:sub(pos))

      cb(test_summary.UnitTestResult)
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Command failed with exit code: " .. code, vim.log.levels.ERROR)
        return {}
      end
    end
  })
end


return M
