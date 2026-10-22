[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$CoreOnly,
    [ValidateSet('ProcessedIngestion','DirectIngestion')][string]$IngestionMode='ProcessedIngestion'
)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if (-not $PSCmdlet.ShouldProcess("$($script:Config.workspaceId)/Dev/Matthieu/OilandGas", 'Deploy scoped demo artifacts')) { return }
Assert-Target
$house = Set-DemoItem 'OilGasEventhouse' 'Eventhouse' @(
    (New-Part 'EventhouseProperties.json' '{}')
)
$properties = @{ databaseType = 'ReadWrite'; parentEventhouseItemId = $house.id } | ConvertTo-Json -Compress
$database = Set-DemoItem $script:Config.databaseName 'KQLDatabase' @(
    (New-Part 'DatabaseProperties.json' $properties)
)
$details = Invoke-Fabric 'GET' "workspaces/$($script:Config.workspaceId)/kqlDatabases/$($database.id)"
if ($details.properties.parentEventhouseItemId -ne $house.id) { throw 'Database parentage mismatch.' }
$statePath = Join-Path $script:Root 'local-only'
New-Item -ItemType Directory -Path $statePath -Force | Out-Null
$stateFile = Join-Path $statePath 'deployment.json'
$state = if (Test-Path -LiteralPath $stateFile) {
    $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -AsHashtable
    if ($saved.workspaceId -ne $script:Config.workspaceId -or $saved.folderId -ne $script:Config.folderId) {
        throw 'Refusing to replace deployment state for a different workspace/folder.'
    }
    $saved
} else { [ordered]@{} }
$core = [ordered]@{
    workspaceId = $script:Config.workspaceId; folderId = $script:Config.folderId
    eventhouseId = $house.id; databaseId = $database.id; databaseName = $script:Config.databaseName
    queryServiceUri = $details.properties.queryServiceUri
    deployedAtUtc = [DateTime]::UtcNow.ToString('o')
}
foreach ($key in $core.Keys) { $state[$key] = $core[$key] }
$state | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $stateFile
foreach ($name in '00-schema.kql','01-normalization.kql','03-functions.kql') {
    Invoke-KqlFile (Join-Path $script:Root "kql\$name")
}
if ($CoreOnly) { return }
$requestedMode=if($PSBoundParameters.ContainsKey('IngestionMode')){$IngestionMode}else{''}
$effectiveMode=Resolve-DemoIngestionMode $state $requestedMode
& (Join-Path $PSScriptRoot 'Deploy-Experience.ps1') -IngestionMode $effectiveMode
