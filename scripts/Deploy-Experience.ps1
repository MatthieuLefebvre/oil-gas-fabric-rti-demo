[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('ProcessedIngestion','DirectIngestion')]
    [string]$IngestionMode='ProcessedIngestion'
)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if (-not $PSCmdlet.ShouldProcess($script:Config.folderPath, 'Deploy Eventstream, dashboard, queryset and reference lakehouse')) { return }
$stateFile = Join-Path $script:Root 'local-only\deployment.json'
$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -AsHashtable
$requestedMode=if($PSBoundParameters.ContainsKey('IngestionMode')){$IngestionMode}else{''}
$IngestionMode=Resolve-DemoIngestionMode $state $requestedMode
$sourceId = '964f865d-69ac-4c16-99bd-d928c9d2b611'
$streamName = 'OilGasTelemetryStream'
$fields = 'RecordDateTime','RecordDateTimeUTC','UnitNum','Source','Name','Value','RecordAdded','ProcessedDate','IngestionTime'
$topology = @{
    compatibilityLevel = '1.1'
    sources = @(@{ id=$sourceId; name='SyntheticTelemetryEndpoint'; type='CustomEndpoint'; properties=@{} })
    streams = @(@{ id='3d26d6c2-d80d-4c9f-aa49-0c09d5905df1'; name=$streamName; type='DefaultStream'; properties=@{}; inputNodes=@(@{name='SyntheticTelemetryEndpoint'}) })
    operators = @()
    destinations = @(@{
        id='d97d60ed-da1e-4233-b2da-b046417ca441'; name='OilGasRawLanding'; type='Eventhouse'
        properties=@{ dataIngestionMode='ProcessedIngestion'; workspaceId=$state.workspaceId; itemId=$state.databaseId
            databaseName=$state.databaseName; tableName='RawTelemetry'; inputSerialization=@{type='Json';properties=@{encoding='UTF8'}} }
        inputNodes=@(@{name=$streamName})
        inputSchemas=@(@{name=$streamName;schema=@{columns=@($fields | ForEach-Object { @{name=$_;type='Nvarchar(max)'} })}})
    })
}
if ($IngestionMode -eq 'DirectIngestion') {
    $topology.destinations[0].id='15a21214-1f2c-4f19-a1a5-836297109c40'
    $topology.destinations[0].name='OilGasRawDirectLanding'
    $topology.destinations[0].properties=@{
        dataIngestionMode='DirectIngestion';workspaceId=$state.workspaceId;itemId=$state.databaseId
        tableName='RawTelemetry';connectionName='OilGasDirectConnection';mappingRuleName='TelemetryJson'
    }
    $topology.destinations[0].Remove('inputSchemas')
}
if ($script:Config.kafkaConnectionId) {
    throw 'Kafka connection provided: qualify its documented connector properties in the portal before changing the fallback topology. See docs\manual-fabric-steps.md.'
}
$topologyJson = $topology | ConvertTo-Json -Depth 40
New-Item -ItemType Directory -Path (Join-Path $script:Root 'fabric\eventstream') -Force | Out-Null
$topologyJson | Set-Content -LiteralPath (Join-Path $script:Root 'fabric\eventstream\definition.json')
$eventstream = Set-DemoItem 'OilGasTelemetryStream' 'Eventstream' @(
    (New-Part 'eventstream.json' $topologyJson)
    (New-Part 'eventstreamProperties.json' '{"retentionTimeInDays":1,"eventThroughputLevel":"Low"}')
) 'eventstream'
$state.eventstreamId=$eventstream.id
$state.eventstreamSourceId=$sourceId
$state.eventstreamIngestionMode=$IngestionMode
$lakehouse = Set-DemoItem 'OilGasReference' 'Lakehouse'
$state.lakehouseId=$lakehouse.id
$queryTexts = @(
    @{title='Current compressor condition';text='LatestCompressorMeasurements() | project SiteId,AssetId,Metric,NumericValue,EngineeringUnit,EventTime,IsStale,Condition'},
    @{title='Synthetic high readings';text='AbnormalCompressorReadings(ago(15m),now())'},
    @{title='Platform ingestion health';text='IngestionHealth(ago(15m),now())'},
    @{title='Tag inventory and freshness';text='SiteTelemetryInventory()'},
    @{title='Duplicate candidates';text='DuplicateCandidates(ago(15m),now())'},
    @{title='Approximate arrival disorder';text='ArrivalOrderDiagnostics(ago(15m),now())'}
)
$ds='4148401e-451c-40d1-ab7f-e8804dd22dfa'
$page='6b48a4d8-d464-44e4-bb89-a1920e2ce18e'
$queries=@();$tiles=@();$tabs=@()
for ($i=0;$i -lt $queryTexts.Count;$i++) {
    $id="a3ab9318-2274-4eb6-9694-$('{0:d12}' -f ($i+1))"
    $queries+=@{id=$id;text=$queryTexts[$i].text;dataSource=@{kind='inline';dataSourceId=$ds};usedVariables=@()}
    $tiles+=@{id="c50a8d18-6f34-4c89-8634-$('{0:d12}' -f ($i+1))";title=$queryTexts[$i].title;visualType='table';pageId=$page
        layout=@{x=($i%2)*12;y=[math]::Floor($i/2)*7;width=12;height=7}
        queryRef=@{kind='query';queryId=$id};visualOptions=@{}}
    $tabs+=@{id=$id;title=$queryTexts[$i].title;content=$queryTexts[$i].text;dataSourceId=$ds}
}
$dashboard=@{schema_version='51';title='Synthetic Oil and Gas Operations';id='172ca905-ed6a-44d4-a127-832746158891'
    autoRefresh=@{enabled=$true};baseQueries=@();parameters=@()
    pages=@(@{name='Operations and platform health';id=$page})
    dataSources=@(@{kind='kusto-trident';scopeId='kusto-trident';clusterUri=$state.queryServiceUri
        database=$state.databaseId;name=$state.databaseName;workspace=$state.workspaceId;id=$ds})
    queries=$queries;tiles=$tiles;isDashboardEditor='True'}
New-Item -ItemType Directory -Path (Join-Path $script:Root 'fabric\dashboard') -Force | Out-Null
$dashboardJson=$dashboard | ConvertTo-Json -Depth 40
$dashboardJson | Set-Content -LiteralPath (Join-Path $script:Root 'fabric\dashboard\RealTimeDashboard.json')
$dashboardItem=Set-DemoItem 'OilGasOperationsDashboard' 'KQLDashboard' @((New-Part 'RealTimeDashboard.json' $dashboardJson))
$state.dashboardId=$dashboardItem.id
$queryset=@{queryset=@{version='1.0.0';dataSources=@(@{id=$ds;clusterUri=$state.queryServiceUri;type='AzureDataExplorer';databaseName=$state.databaseName});tabs=$tabs}}
$querysetItem=Set-DemoItem 'OilGasOperationalQueries' 'KQLQueryset' @((New-Part 'RealTimeQueryset.json' ($queryset|ConvertTo-Json -Depth 30)))
$state.querysetId=$querysetItem.id
$state | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $stateFile
Write-Host 'Experience items deployed. Source is explicitly the synthetic custom-endpoint fallback, not a verified external Kafka connector.'
