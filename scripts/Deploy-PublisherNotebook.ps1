[CmdletBinding(SupportsShouldProcess)]
param([ValidateRange(1,3000)][int]$Count=12,[ValidateRange(0.1,100)][double]$Rate=1)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if(-not $PSCmdlet.ShouldProcess($script:Config.folderPath,'Deploy finite pure-Python publisher notebook using the shared generator and in-memory credentials')){return}
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$memory=[IO.MemoryStream]::new()
$archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
try {
    foreach($name in 'simulator\__init__.py','simulator\telemetry.py','simulator\publish.py','data\measurements.csv'){
        $entry=$archive.CreateEntry($name.Replace('\','/'))
        $stream=$entry.Open()
        try {
            $bytes=[IO.File]::ReadAllBytes((Join-Path $script:Root $name))
            $stream.Write($bytes,0,$bytes.Length)
        } finally {$stream.Dispose()}
    }
} finally {$archive.Dispose()}
try {$bundle=[Convert]::ToBase64String($memory.ToArray())}finally{$memory.Dispose()}
$code=@"
import base64, io, json, sys, tempfile, zipfile
from dataclasses import asdict
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
import notebookutils

with tempfile.TemporaryDirectory(prefix="oilgas-publisher-") as directory:
    with zipfile.ZipFile(io.BytesIO(base64.b64decode("$bundle"))) as archive:
        archive.extractall(directory)
    sys.path.insert(0, directory)
    from simulator.telemetry import iter_live
    from simulator.publish import EventHubsRestSender, publish
    token = notebookutils.credentials.getToken("pbi")
    request = Request(
        "https://api.fabric.microsoft.com/v1/workspaces/$($s.workspaceId)/eventstreams/$($s.eventstreamId)/sources/$($s.eventstreamSourceId)/connection",
        headers={"Authorization": "Bearer " + token, "Accept": "application/json"},
    )
    try:
        with urlopen(request, timeout=30) as response:
            connection = json.load(response)
    except HTTPError as error:
        notebookutils.notebook.exit(json.dumps({"status": "Failed", "stage": "FabricSourceConnection", "httpStatus": error.code}))
    except URLError:
        notebookutils.notebook.exit(json.dumps({"status": "Failed", "stage": "FabricSourceConnection", "code": "NetworkError"}))
    if connection["type"] != "CustomEndpoint":
        raise RuntimeError("Unexpected source type")
    sender = EventHubsRestSender(
        {"TELEMETRY_EVENTHUB_CONNECTION_STRING": connection["accessKeys"]["primaryConnectionString"]},
        timeout=15, retries=0,
    )
    connection = None
    token = None
    request = None
    summary = publish(iter_live($Count, rate=$Rate, scenario=True), sender, rate=$Rate, concurrency=1, limit=$Count)
    result = asdict(summary)
    print(json.dumps(result))
    result["status"] = "Failed" if summary.Failed or summary.Accepted != $Count else "Succeeded"
    notebookutils.notebook.exit(json.dumps(result))
"@
$notebook=@{
    nbformat=4;nbformat_minor=5
    cells=@(@{cell_type='code';source=@($code);execution_count=$null;outputs=@();metadata=@{}})
    metadata=@{
        kernel_info=@{name='jupyter';jupyter_kernel_name='python3.11'}
        kernelspec=@{name='jupyter';display_name='Jupyter'}
        language_info=@{name='python'}
        microsoft=@{language='python';language_group='jupyter_python'}
        dependencies=@{lakehouse=@{default_lakehouse=$s.lakehouseId;default_lakehouse_workspace_id=$s.workspaceId;default_lakehouse_name='OilGasReference'}}
        sessionKeepAliveTimeout=0
    }
}
$json=$notebook|ConvertTo-Json -Depth 30
$item=Set-DemoItem 'OilGasPublishTelemetry' 'Notebook' @((New-Part 'notebook-content.ipynb' $json)) 'ipynb'
$s.publisherNotebookId=$item.id
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
Write-Host 'Pure-Python publisher deployed. No secrets are stored in its definition; the run is finite and must be validated at Eventhouse.'
