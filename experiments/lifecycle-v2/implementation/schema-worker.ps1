param([Parameter(Mandatory)][string]$SchemaPath)
$ErrorActionPreference = 'Stop'
$stage = 'read-schema'
try {
    $stage = 'configure-utf8'
    # Python sends UTF-8 JSON lines; Windows console defaults must not decode them as CP932.
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false, $true)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false, $true)
    $stage = 'read-schema'
    $schemaText = [System.IO.File]::ReadAllText($SchemaPath)
    $schemaObject = $schemaText | ConvertFrom-Json -AsHashtable
    if ($schemaObject['$schema'] -ne 'https://json-schema.org/draft/2020-12/schema') {
        throw 'Unsupported schema dialect'
    }
    # Test-Json loads the installed JsonSchema.Net assembly without downloading packages.
    $null = Test-Json -Json '{}' -Schema '{"type":"object"}'
    $options = [Json.Schema.EvaluationOptions]::new()
    $options.RequireFormatValidation = $true
    # The complete metaschema is evaluated explicitly below. Enabling automatic
    # self-validation while evaluating that metaschema recurses in this runtime.
    $options.ValidateAgainstMetaSchema = $false
    $options.OutputFormat = [Json.Schema.OutputFormat]::List
    $schemaNode = [System.Text.Json.Nodes.JsonNode]::Parse($schemaText)
    $stage = 'evaluate-metaschema'
    $meta = [Json.Schema.MetaSchemas]::Draft202012.Evaluate($schemaNode, $options)
    if (-not $meta.IsValid) { throw 'Draft2020-12 metaschema validation failed' }
    $stage = 'compile-instance-schema'
    $schema = [Json.Schema.JsonSchema]::FromText($schemaText)
    $ready = @{ready = $true; metaschema = $true; engine = [Json.Schema.JsonSchema].Assembly.GetName().Name; engine_version = [Json.Schema.JsonSchema].Assembly.GetName().Version.ToString(); powershell = $PSVersionTable.PSVersion.ToString(); framework = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription; format_assertion = $true; explicit_metaschema = $true; input_codepage = [Console]::InputEncoding.CodePage; output_codepage = [Console]::OutputEncoding.CodePage}
    [Console]::WriteLine(($ready | ConvertTo-Json -Compress))
    while ($null -ne ($line = [Console]::ReadLine())) {
        try {
            $instance = [System.Text.Json.Nodes.JsonNode]::Parse($line)
            $result = $schema.Evaluate($instance, $options)
            [Console]::WriteLine((@{valid = $result.IsValid} | ConvertTo-Json -Compress))
        }
        catch {
            [Console]::WriteLine('{"valid":false,"error":"evaluation rejected"}')
        }
    }
}
catch {
    [Console]::Error.WriteLine(('schema-initialization stage={0}; exception={1}' -f $stage, $_.Exception.GetType().FullName))
    [Console]::WriteLine((@{ready = $false; error = 'schema engine initialization failed'; stage = $stage} | ConvertTo-Json -Compress))
    exit 1
}
