local M = {}

local script_src = [[
#r "nuget: Newtonsoft.Json"
open System
open System.IO
open System.Xml
open Newtonsoft.Json.Linq
open Newtonsoft.Json

let convertXmlElementToJson (xmlElement: XmlElement) : string =
    let jsonString = JsonConvert.SerializeXmlNode(xmlElement, Newtonsoft.Json.Formatting.None)
    jsonString

let main (argv: string[]) =
    if argv.Length <> 2 then
        printfn "Usage: fsi script.fsx <xml-file-path> <out-file-path>"
        1
    else
        try
            let filePath = argv.[0]
            let outputFilePath = argv.[1]
            if File.Exists(filePath) then
                let xmlDoc = new XmlDocument()
                xmlDoc.Load(filePath)
                use writer = new StreamWriter(outputFilePath, append = false)
                for propertyGroup in xmlDoc.GetElementsByTagName("PropertyGroup") do
                    let json = convertXmlElementToJson(propertyGroup :?> XmlElement)
                    writer.WriteLine(json)
                for packageReference in xmlDoc.GetElementsByTagName("PackageReference") do
                    let json = convertXmlElementToJson(packageReference :?> XmlElement)
                    writer.WriteLine(json)
                for projectReference in xmlDoc.GetElementsByTagName("ProjectReference") do
                    let json = convertXmlElementToJson(projectReference :?> XmlElement)
                    writer.WriteLine(json)
                0
            else
                printfn "Error: File not found - %s" filePath
                1
        with
        | :? System.Exception as ex ->
            printfn "Error: %s" ex.Message
            1

main fsi.CommandLineArgs.[1..]
]]

local script_name = "project_parser.fsx"

M.ensure_and_get_fsx_path = function()
  return require("easy-dotnet.scripts.utils").ensure_and_get_fsx_path(script_src, script_name)
end

return M
