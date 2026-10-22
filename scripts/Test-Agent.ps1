[CmdletBinding()]
param(
    [switch]$DiscoverOnly,
    [ValidateSet('None','HighCount','OntologyPath','GraphPath','CurrentStale','SiteInventory','CompareHistorical','AmbiguousAsset')][string]$AcceptanceCase='None',
    [string]$Question=''
)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
. (Join-Path $PSScriptRoot 'Agent.Acceptance.ps1')
if(-not $Question){
    $questions=@{
        HighCount='Using OilGasOperationsDB, how many unique eligible synthetic high-pressure readings occurred from 2026-10-20T11:00:00Z through 2026-10-20T12:00:00Z? Use AbnormalCompressorReadings and report the observation window and units.'
        CurrentStale='Using OilGasOperationsDB and LatestCompressorMeasurements(), are any readings fresh now? Return the 12 measurements with FreshCount, StaleCount, MissingCount, AsOfUtc, MeasurementId, AssetId, SiteId, Metric, EngineeringUnit, EventTime, FreshnessStatus. Label present old readings Stale and absent readings Missing. Use actual UTC as-of time and 60-second freshness, never a healthy zero.'
        SiteInventory="What operational telemetry is registered at SITE-A? Use SiteTelemetryInventory('SITE-A') and return all six measurements with MeasurementId, AssetId, SiteId, Metric, EngineeringUnit, actual AsOfUtc, EventTime, IsStale. Do not include another site or label stale observations as current."
        CompareHistorical='Compare CMP-A1 and CMP-B1 from 2026-10-20T11:00:00Z through 2026-10-20T12:00:00Z using CompareCompressors. Keep each asset, metric and engineering unit separate. Return six rows with AssetId, Metric, EngineeringUnit, Average, Minimum, Maximum rounded to three decimal places, Samples, LatestTime, ObservationWindowStart, ObservationWindowEnd. Report this as historical synthetic data, not current conditions.'
        AmbiguousAsset='What is wrong with Compressor 1? Do not assume a site. Return both scoped assets and their six measurements using LatestCompressorMeasurements, with MeasurementId, AssetId, SiteId, Metric, EngineeringUnit, actual AsOfUtc, EventTime, IsStale. State that stale data cannot establish current conditions, and explicitly say this is not a diagnosis.'
        GraphPath='Use only OilGasOperationalOntologyGraph to trace SITE-A through Battery and System to CMP-A1, THR-A1 and the discharge-pressure Measurement. Return SiteId, BatteryId, SystemId, CompressorId, ComponentId, MeasurementId, Source, UnitNum, Name, EngineeringUnit. Preserve native string values without adding literal quote characters; identify the ontology-backed GraphModel source.'
        OntologyPath='Use only OilGasOperationalOntology to trace SITE-A through Battery and System to CMP-A1, THR-A1 and the discharge-pressure Measurement. Return SiteId, BatteryId, SystemId, CompressorId, ComponentId, MeasurementId, Source, UnitNum, Name, EngineeringUnit. If unavailable, say so; do not substitute a registry query.'
    }
    $questionCase=if($AcceptanceCase -eq 'None'){'HighCount'}else{$AcceptanceCase}
    $Question=$questions[$questionCase]
}
Assert-Target
$s=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$item=Invoke-Fabric 'GET' "workspaces/$($s.workspaceId)/items/$($s.dataAgentId)"
if($item.type -ne 'DataAgent' -or $item.folderId -ne $s.folderId){throw 'Unexpected agent target.'}
$endpoint="https://api.fabric.microsoft.com/v1/mcp/workspaces/$($s.workspaceId)/dataagents/$($s.dataAgentId)/agent"
$script:AgentHeaders=@{
    Authorization='Bearer '+(Get-AccessToken 'https://api.fabric.microsoft.com')
    Accept='application/json, text/event-stream'
}
function Invoke-AgentRpc([hashtable]$Message) {
    $response=Invoke-WebRequest -Method Post -Uri $endpoint -Headers $script:AgentHeaders `
        -ContentType 'application/json' -Body ($Message|ConvertTo-Json -Depth 40 -Compress) -TimeoutSec 180
    if($response.Headers.ContainsKey('Mcp-Session-Id')){
        $script:AgentHeaders['Mcp-Session-Id']=[string]@($response.Headers['Mcp-Session-Id'])[0]
    }
    if([string]::IsNullOrWhiteSpace($response.Content)){return $null}
    $content=$response.Content.Trim()
    if($content.StartsWith('{')){$messages=@($content|ConvertFrom-Json -Depth 100)}else{
        $messages=@([regex]::Matches($content,'(?m)^data:\s*(.+)\r?$')|ForEach-Object{
            $_.Groups[1].Value|ConvertFrom-Json -Depth 100
        })
    }
    if(-not $Message.ContainsKey('id')){
        foreach($message in $messages){
            if($message.PSObject.Properties['error']){throw ($message.error|ConvertTo-Json -Depth 20 -Compress)}
        }
        return $null
    }
    $reply=@($messages|Where-Object {$_.PSObject.Properties['id'] -and $_.id -eq $Message.id})
    if($reply.Count -ne 1){throw "MCP $($Message.method) did not return one matching JSON-RPC response."}
    if($reply[0].PSObject.Properties['error']){throw ($reply[0].error|ConvertTo-Json -Depth 20 -Compress)}
    return $reply[0].result
}
try {
    $initialized=Invoke-AgentRpc @{
        jsonrpc='2.0';id=1;method='initialize'
        params=@{protocolVersion='2025-03-26';capabilities=@{};clientInfo=@{name='OilGasValidation';version='1.0'}}
    }
    $script:AgentHeaders['MCP-Protocol-Version']=$initialized.protocolVersion
    Invoke-AgentRpc @{jsonrpc='2.0';method='notifications/initialized'}|Out-Null
    $tools=Invoke-AgentRpc @{jsonrpc='2.0';id=2;method='tools/list';params=@{}}
    if($DiscoverOnly){$tools|ConvertTo-Json -Depth 30;return}
    if(@($tools.tools).Count -ne 1){throw 'Expected one documented Data Agent query tool.'}
    $tool=$tools.tools[0]
    $required=@($tool.inputSchema.required)
    if($required.Count -ne 1 -or $tool.inputSchema.properties.($required[0]).type -ne 'string'){
        throw 'Inspect the discovered query tool schema before supplying its arguments.'
    }
    $arguments=@{};$arguments[$required[0]]=$Question
    $answer=Invoke-AgentRpc @{jsonrpc='2.0';id=3;method='tools/call';params=@{name=$tool.name;arguments=$arguments}}
    if(($answer.PSObject.Properties['isError'] -and $answer.isError) -or -not $answer.content){
        throw "Agent tool failed: $($answer|ConvertTo-Json -Depth 30 -Compress)"
    }
    $expectedRows=@()
    if($AcceptanceCase -eq 'CompareHistorical'){
        $groundTruth=Invoke-Kql (Get-Content -LiteralPath (Join-Path $script:Root 'agent\compare-fixture.kql') -Raw)
        $table=$groundTruth.Tables[0]
        $expectedRows=@(foreach($record in $table.Rows){
            $fields=@{}
            for($i=0;$i -lt $table.Columns.Count;$i++){$fields[$table.Columns[$i].ColumnName]=$record[$i]}
            [pscustomobject]$fields
        })
        if($expectedRows.Count -ne 6){throw 'The approved comparison window must have six independent ground-truth rows.'}
    }
    $accepted=$false
    if($AcceptanceCase -ne 'None'){$accepted=Test-AgentAnswer -Response $answer -Case $AcceptanceCase -ExpectedRows $expectedRows}
    $evidence=@{
        observedAtUtc=[DateTime]::UtcNow.ToString('o');workspaceId=$s.workspaceId;agentId=$s.dataAgentId
        question=$Question;toolName=$tool.name;response=$answer
        rpcCallCompleted=$true;acceptanceCase=$AcceptanceCase;semanticAcceptanceVerified=$accepted
        underlyingGeneratedQueryVerified=$false
        independentlyQueriedComparison=$expectedRows
    }
    $path=Join-Path $script:Root ("local-only\agent-evaluation-"+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'-'+[Guid]::NewGuid().ToString('N')+'.json')
    $evidence|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $path
    if($AcceptanceCase -ne 'None' -and -not $accepted){
        throw "Agent answer failed $AcceptanceCase CSV acceptance. Inspect preserved evidence: $path"
    }
    $answer|ConvertTo-Json -Depth 40
} finally {
    $script:AgentHeaders.Clear()
}
