local M = {}

local file_template = [[
//v5
#r "nuget: Newtonsoft.Json"
open System
open System.IO
open System.Xml
open Newtonsoft.Json.Linq
open Newtonsoft.Json

let xmlToJson (xml: string) : JObject =
    let xmlDoc = new XmlDocument()
    xmlDoc.LoadXml(xml)
    let jsonString = JsonConvert.SerializeXmlNode(xmlDoc, Newtonsoft.Json.Formatting.Indented)
    JObject.Parse(jsonString)

let transformTestCase (testCase: JObject) : JProperty =
    let testId = testCase.["@testId"].ToString()
    let newTestCase = new JObject()
    newTestCase.["outcome"] <- testCase.["@outcome"]
    newTestCase.["id"] <- testCase.["@testId"]

    let errorInfo = testCase.SelectToken("$.Output.ErrorInfo")
    if errorInfo <> null && errorInfo.["StackTrace"] <> null then
        newTestCase.["stackTrace"] <- errorInfo.["StackTrace"]
    if errorInfo <> null && errorInfo.["Message"] <> null then
        newTestCase.["message"] <- errorInfo.["Message"]

    new JProperty(testId, newTestCase)

let extractAndTransformResults (jsonObj: JObject) : JObject option =
    let resultsToken = jsonObj.SelectToken("$.TestRun.Results.UnitTestResult")
    match resultsToken with
    | null -> None
    | _ ->
        let results =
            match resultsToken.Type with
            | JTokenType.Array -> resultsToken :?> JArray
            | _ -> new JArray(resultsToken)

        let transformedResults = new JObject()

        for testCase in results do
            let property = transformTestCase (testCase :?> JObject)
            let testId = property.Name

            if transformedResults.ContainsKey(testId) then
                let outcome = property.Value.["outcome"].ToString()
                // if there are multiple results with the same testId, we want to know if any of them did not pass
                if not (String.Equals(outcome, "passed", StringComparison.OrdinalIgnoreCase)) then
                    transformedResults.[testId] <- property.Value
            else
                transformedResults.Add(property)

        Some transformedResults

let main (argv: string[]) =
    if argv.Length <> 2 then
        printfn "Usage: fsi script.fsx <xml-file-path> <out-file-path>"
        1
    else
        try
            let filePath = argv.[0]
            let outputFilePath = argv.[1]
            if File.Exists(filePath) then
                let xmlContent = File.ReadAllText(filePath)
                let jsonObj = xmlToJson(xmlContent)
                match extractAndTransformResults(jsonObj) with
                | Some results ->
                    use writer = new StreamWriter(outputFilePath, append = true)
                    for result in results.Properties() do
                        let resultJson = JsonConvert.SerializeObject(result.Value, Formatting.None)
                        writer.WriteLine(resultJson)
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

local script_name = "test_parser.fsx"

---@return string
local ensure_and_get_fsx_path = function() return require("easy-dotnet.scripts.utils").ensure_and_get_fsx_path(file_template, script_name) end

--- @class TestCase
--- @field id string
--- @field stackTrace string | nil
--- @field message string | nil
--- @field outcome TestResult

---@param xml_path string
M.xml_to_json = function(xml_path, cb)
  local fsx_file = ensure_and_get_fsx_path()
  local outfile = vim.fs.normalize(os.tmpname())
  local command = string.format("dotnet fsi %s %s %s", fsx_file, xml_path, outfile)
  ---@type TestCase[]
  local tests = {}
  local stderr = {}
  vim.fn.jobstart(command, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data) stderr = data end,
    on_exit = function(_, code)
      if code ~= 0 then
        vim.notify("Command failed with exit code: " .. code, vim.log.levels.ERROR)
        print(vim.inspect(stderr))
        return {}
      else
        local file = io.open(outfile)
        if file == nil then
          print("Test parser script emitted no file for " .. xml_path)
          cb({})
          return
        end

        for line in file:lines() do
          local success, json_test = pcall(function() return vim.fn.json_decode(line) end)

          if success then
            if #line ~= 2 then table.insert(tests, json_test) end
          else
            print("Malformed JSON: " .. line)
          end
        end

        local success = pcall(function() os.remove(outfile) end)

        if not success then print("Failed to delete tmp file " .. outfile) end
        cb(tests)
      end
    end,
  })
end

return M
