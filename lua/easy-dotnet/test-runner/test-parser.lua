local M = {}

local file_template = [[
//v2
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
    let testName = testCase.["@testName"].ToString()
    let testId = testCase.["@testId"].ToString()
    let newTestCase = new JObject()
    newTestCase.["outcome"] <- testCase.["@outcome"]
    newTestCase.["id"] <- testCase.["@testId"]

    let errorInfo = testCase.SelectToken("$.Output.ErrorInfo")
    if errorInfo <> null && errorInfo.["StackTrace"] <> null then
        newTestCase.["stackTrace"] <- errorInfo.["StackTrace"]

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

        let transformedResults = new JObject(
            results
            |> Seq.map (fun testCase -> transformTestCase (testCase :?> JObject))
        )

        Some transformedResults

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
                match extractAndTransformResults(jsonObj) with
                | Some results ->
                    for result in results.Properties() do
                        let resultJson = JsonConvert.SerializeObject(result.Value, Formatting.None)
                        printfn "%s" resultJson
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
  local dir = require("easy-dotnet.constants").get_data_directory()
  local filepath = vim.fs.joinpath(dir, "test_parser.fsx")
  local file = io.open(filepath, "r")
  if file then
    local v = file:read("l"):match("//v(%d+)")
    file:close()
    local new_v = file_template:match("//v(%d+)")
    if v ~= new_v then
      local overwrite_file = io.open(filepath, "w+")
      if overwrite_file == nil then
        error("Failed to create the file: " .. filepath)
      end
      vim.notify("Updating test_parser.fsx", vim.log.levels.INFO)
      overwrite_file:write(file_template)
      overwrite_file:close()
    end
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


--- @class TestCase
--- @field id string
--- @field stackTrace string | nil
--- @field outcome string

---@param xml_path string
M.xml_to_json = function(xml_path, cb)
  local fsx_file = ensure_and_get_fsx_path()
  local command = string.format("dotnet fsi %s '%s'", fsx_file, xml_path)
  ---@type TestCase[]
  local tests = {}
  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stderr = function(_, data)
    end,
    ---@param data string[]
    on_stdout = function(_, data)
      --Emitting line by line to avoid memory issues with json parsing in vim
      for _, stdout_line in ipairs(data) do
        if stdout_line:match("{") then
          local success, test = pcall(function() return vim.fn.json_decode(stdout_line) end)
          if success ~= false then
            table.insert(tests, test)
          else
            print("Malformed json: " .. success)
          end
        end
      end
      cb(tests)
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

