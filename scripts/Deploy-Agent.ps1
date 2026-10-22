[CmdletBinding(SupportsShouldProcess)]
param([switch]$IncludeOntology,[switch]$IncludeGraph)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if(-not $PSCmdlet.ShouldProcess($script:Config.folderPath,'Create draft KQL-grounded Data Agent; no chat or ontology-grounding claim')){return}
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$instructions=Get-Content -LiteralPath (Join-Path $script:Root 'agent\instructions.md') -Raw
$base='https://developer.microsoft.com/json-schemas/fabric/item/dataAgent/definition'
$source=[ordered]@{
    type='kusto';'$schema'="$base/dataSource/1.0.0/schema.json";artifactId=$s.databaseId;workspaceId=$s.workspaceId
    displayName=$s.databaseName;dataSourceInstructions=$instructions;userDescription='Synthetic operational telemetry, curated KQL functions, units and asset hierarchy'
    metadata=@{};elements=@()
}
$fewshots=@{ '$schema'="$base/fewShots/1.0.0/schema.json";fewShots=@(
    @{id='eb73c067-8f0f-4698-9c7b-0a53cef7cf91';question='Which compressors have fresh synthetic high pressure?';query="LatestCompressorMeasurements() | where not(IsStale) and Condition == 'Synthetic high'"},
    @{id='6170eb29-3ee0-4417-9d90-63b3ee09fb03';question='What operational telemetry exists for site SITE-A?';query="SiteTelemetryInventory('SITE-A') | project MeasurementId,AssetId,SiteId,Metric,EngineeringUnit,AsOfUtc,EventTime,IsStale"},
    @{id='b83b13bb-8100-49af-9544-88e589125230';question='Which readings exceeded a synthetic threshold in the last 15 minutes?';query='AbnormalCompressorReadings(ago(15m),now())'},
    @{id='fa3b0e32-916a-42b8-a905-21867e8ef707';question='How many unique eligible synthetic high-pressure readings occurred from 2026-10-20T11:00:00Z through 2026-10-20T12:00:00Z?';query="AbnormalCompressorReadings(datetime(2026-10-20T11:00:00Z),datetime(2026-10-20T12:00:00Z)) | summarize UniqueHighPressureReadings=count() by EngineeringUnit"},
    @{id='cb61c8d4-c068-4f83-a933-373f518d1552';question='What is wrong with Compressor 1 at both scoped sites?';query="LatestCompressorMeasurements() | where AssetId in ('CMP-A1','CMP-B1') | project MeasurementId,AssetId,SiteId,Metric,EngineeringUnit,AsOfUtc,EventTime,IsStale"},
    @{id='32c8ef9e-a92b-40d8-9ba0-d003346323e0';question='Compare CMP-A1 and CMP-B1 over the historical fixture window, keeping all metrics and units separate.';query=(Get-Content -LiteralPath (Join-Path $script:Root 'agent\compare-fixture.kql') -Raw)}
)}
$parts=@(
    (New-Part 'Files/Config/data_agent.json' (@{'$schema'="$base/dataAgent/2.1.0/schema.json"}|ConvertTo-Json)),
    (New-Part 'Files/Config/draft/stage_config.json' (@{'$schema'="$base/stageConfiguration/1.0.0/schema.json";aiInstructions=$instructions}|ConvertTo-Json)),
    (New-Part 'Files/Config/draft/kusto-OilGasOperationsDB/datasource.json' ($source|ConvertTo-Json -Depth 20)),
    (New-Part 'Files/Config/draft/kusto-OilGasOperationsDB/fewshots.json' ($fewshots|ConvertTo-Json -Depth 20))
)
if($IncludeOntology){
    $package=Get-Content -LiteralPath (Join-Path $script:Root 'ontology\definition.json') -Raw|ConvertFrom-Json
    $ontologySource=@{
        '$schema'="$base/ontology/1.0.0/schema.json";artifactId=$s.ontologyId
        workspaceId=$s.workspaceId;displayName='OilGasOperationalOntology'
        entitiesWithUserAuthoredDescriptions=@()
        elements=@($package.entities|ForEach-Object {
            @{id=[string]$_.id;is_selected=$true;display_name=$_.type;type='ontology.entity'
                description="Synthetic $($_.type), scoped identity and operational context";children=@()}
        })
    }
    if($IncludeGraph){
        if(-not $s.graphModelId){throw 'Run Test-Ontology.ps1 to discover and verify the actual ontology backing GraphModel first.'}
        $graph=Invoke-Fabric 'GET' "workspaces/$($s.workspaceId)/items/$($s.graphModelId)"
        if($graph.type -ne 'GraphModel' -or $graph.folderId -ne $s.folderId){throw 'Backing GraphModel is outside the approved folder/type.'}
        $graphSource=[ordered]@{
            type='graph';'$schema'="$base/dataSource/1.0.0/schema.json"
            artifactId=$s.graphModelId;workspaceId=$s.workspaceId;displayName='OilGasOperationalOntologyGraph'
            dataSourceInstructions=$instructions;userDescription='Actual ontology backing GraphModel: six synthetic node types and six relationship types. Native graph context, not telemetry.'
            metadata=@{};elements=@()
        }
        $parts+=New-Part 'Files/Config/draft/graph-OilGasOperationalOntologyGraph/datasource.json' ($graphSource|ConvertTo-Json -Depth 20)
        $graphFewshots=@{
            '$schema'="$base/fewShots/1.0.0/schema.json"
            fewShots=@(@{
                id='15be1e6d-ae11-497e-b9aa-7a670e270f03'
                question='Trace SITE-A through its Battery and System to CMP-A1, THR-A1 and the discharge-pressure Measurement using the ontology-backed GraphModel.'
                query=(Get-Content -LiteralPath (Join-Path $script:Root 'ontology\site-a-pressure.gql') -Raw).Replace('AS AssetId','AS CompressorId')
            })
        }
        $parts+=New-Part 'Files/Config/draft/graph-OilGasOperationalOntologyGraph/fewshots.json' ($graphFewshots|ConvertTo-Json -Depth 20)
    }
    $parts[1]=New-Part 'Files/Config/draft/stage_config.json' (@{
        '$schema'="$base/stageConfiguration/1.0.0/schema.json";aiInstructions=$instructions
        experimental=@{enableExperimentalFeatures=$true}
    }|ConvertTo-Json -Depth 10)
    $parts+=New-Part 'Files/Config/draft/ontologies/OilGasOperationalOntology/ontology.json' ($ontologySource|ConvertTo-Json -Depth 20)
}
$item=Set-DemoItem 'OilGasOperationsAgent' 'DataAgent' $parts
$s.dataAgentId=$item.id
$s.dataAgentOntologyConfigured=[bool]$IncludeOntology
$s.dataAgentGraphConfigured=[bool]$IncludeGraph
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
& (Join-Path $PSScriptRoot 'Select-AgentSources.ps1')
Write-Host 'Agent draft configured. Source selection must be read back and actual conversation evaluated before claiming runtime grounding.'
