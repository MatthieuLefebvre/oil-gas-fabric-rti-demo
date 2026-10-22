[CmdletBinding()]
param([switch]$Fixture)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$state=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$items=@(Get-FabricCollection "workspaces/$($state.workspaceId)/items?rootFolderId=$($state.folderId)&recursive=false")
$expected=@{
    eventhouseId='Eventhouse';databaseId='KQLDatabase';eventstreamId='Eventstream'
    lakehouseId='Lakehouse';dashboardId='KQLDashboard';querysetId='KQLQueryset'
    referenceNotebookId='Notebook';ontologyId='Ontology';dataAgentId='DataAgent'
}
foreach($optional in @(@('publisherNotebookId','Notebook'),@('activatorId','Reflex'))){
    if($state.PSObject.Properties[$optional[0]]){$expected[$optional[0]]=$optional[1]}
}
foreach($entry in $expected.GetEnumerator()){
    $id=$state.($entry.Key)
    $match=@($items|Where-Object id -eq $id)
    if($match.Count -ne 1 -or $match[0].type -ne $entry.Value -or $match[0].folderId -ne $state.folderId){
        throw "Deployed $($entry.Key) is missing or outside the approved folder/type."
    }
}
$lakehouse=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/lakehouses/$($state.lakehouseId)/tables"
$names=@($lakehouse.data|ForEach-Object {$_.name})
$reference=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\reference-tables.json') -Raw|ConvertFrom-Json -AsHashtable
foreach($name in $reference.Keys){if($name -notin $names){throw "Lakehouse table not registered: $name"}}
$agent=Invoke-Fabric 'POST' "workspaces/$($state.workspaceId)/items/$($state.dataAgentId)/getDefinition"
$sourcePart=@($agent.definition.parts|Where-Object path -like 'Files/Config/draft/kusto-*/datasource.json')
if($sourcePart.Count -ne 1){throw 'Expected exactly one explicit draft KQL source.'}
$source=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sourcePart[0].payload))|ConvertFrom-Json
if($source.type -ne 'kusto' -or $source.artifactId -ne $state.databaseId -or $source.workspaceId -ne $state.workspaceId){
    throw 'Agent source does not resolve to the approved demo database.'
}
$selection=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/dataAgents/$($state.dataAgentId)/staging/datasources/$($state.databaseId)"
if($selection.selectionState -ne 'Partial'){throw 'Expected the explicitly selected curated KQL schema, not an empty or entire source.'}
$intended=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\agent-selection.json') -Raw|ConvertFrom-Json
if($intended.sourceId -ne $state.databaseId -or @($intended.selected).Count -ne 14){throw 'Curated source selection evidence is missing or mismatched.'}
$catalogs=@(Get-FabricCollection "workspaces/$($state.workspaceId)/dataAgents/$($state.dataAgentId)/staging/datasources/$($state.databaseId)/elements"|Where-Object type -in 'Functions','Tables')
if($catalogs.Count -ne 2){throw 'Expected both KQL schema catalogs.'}
$actualSelected=@(foreach($catalog in $catalogs){
    $elements=Get-FabricCollection ("workspaces/$($state.workspaceId)/dataAgents/$($state.dataAgentId)/staging/datasources/$($state.databaseId)/elements?rootId="+[uri]::EscapeDataString($catalog.id))
    $elements|Where-Object isSelected|Select-Object -ExpandProperty id
})
if($actualSelected.Count -ne 14 -or @(Compare-Object @($intended.selected.id) $actualSelected).Count){
    throw 'Actual selected KQL schema differs from the intended eleven functions and three registries.'
}
$ontologySource=@($agent.definition.parts|Where-Object path -eq 'Files/Config/draft/ontologies/OilGasOperationalOntology/ontology.json')
if($ontologySource.Count -ne 1){throw 'Native ontology agent source is missing.'}
$ontologySelection=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ontologySource[0].payload))|ConvertFrom-Json
if($ontologySelection.artifactId -ne $state.ontologyId -or
    @($ontologySelection.elements|Where-Object is_selected -eq $true).Count -ne 6){
    throw 'Agent ontology selection does not match the six approved entities.'
}
$graphAgentConfigured=[bool]($state.PSObject.Properties['dataAgentGraphConfigured'] -and $state.dataAgentGraphConfigured)
if($graphAgentConfigured){
    $graphPart=@($agent.definition.parts|Where-Object path -eq 'Files/Config/draft/graph-OilGasOperationalOntologyGraph/datasource.json')
    if($graphPart.Count -ne 1){throw 'Ontology backing graph datasource is missing.'}
    $graphAgentSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($graphPart[0].payload))|ConvertFrom-Json
    if($graphAgentSource.type -ne 'graph' -or $graphAgentSource.artifactId -ne $state.graphModelId -or
        $graphAgentSource.workspaceId -ne $state.workspaceId){throw 'Agent graph source points outside the verified backing GraphModel.'}
    $graphElements=@(Get-FabricCollection "workspaces/$($state.workspaceId)/dataAgents/$($state.dataAgentId)/staging/datasources/$($state.graphModelId)/elements")
    if($graphElements.Count -ne 12 -or @($graphElements|Where-Object isSelected).Count -ne 12){throw 'Expected six selected graph node types and six selected edge types.'}
}
foreach($draft in @($agent.definition.parts|Where-Object {
    $_.path -like 'Files/Config/draft/*/datasource.json' -or
    $_.path -like 'Files/Config/draft/ontologies/*/ontology.json'
})){
    $published=@($agent.definition.parts|Where-Object path -eq $draft.path.Replace('/draft/','/published/'))
    if($published.Count -ne 1){throw "Published source part is missing: $($draft.path)"}
    $draftSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($draft.payload))|ConvertFrom-Json
    $publishedSource=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($published[0].payload))|ConvertFrom-Json
    if($publishedSource.artifactId -ne $draftSource.artifactId -or $publishedSource.workspaceId -ne $draftSource.workspaceId){
        throw 'Published datasource reference differs from the verified staging source.'
    }
    if($draftSource.PSObject.Properties['type'] -and
        (-not $publishedSource.PSObject.Properties['type'] -or $publishedSource.type -ne $draftSource.type)){
        throw 'Published datasource type differs from staging.'
    }
}
$activatorStopped=$false
$ruleConfigured=[bool]($state.PSObject.Properties['activatorRuleConfigured'] -and $state.activatorRuleConfigured)
if($state.PSObject.Properties['activatorId']){
    $reflex=Invoke-Fabric 'POST' "workspaces/$($state.workspaceId)/items/$($state.activatorId)/getDefinition"
    $part=@($reflex.definition.parts|Where-Object path -eq 'ReflexEntities.json')
    if($part.Count -ne 1){throw 'Activator definition is missing.'}
    $entities=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part[0].payload))|ConvertFrom-Json
    $sources=@($entities|Where-Object type -eq 'kqlSource-v1')
    if($sources.Count -ne 1 -or -not $sources[0].payload.runSettings.isStopped -or
        $sources[0].payload.eventhouseItem.itemId -ne $state.databaseId -or
        $sources[0].payload.eventhouseItem.workspaceId -ne $state.workspaceId){
        throw 'Activator source is not stopped or points outside this demo.'
    }
    $rules=@($entities|Where-Object {$_.payload.PSObject.Properties['definition'] -and $_.payload.definition.type -eq 'Rule'})
    foreach($rule in $rules){
        if($rule.payload.definition.settings.shouldRun -or $rule.payload.definition.settings.shouldApplyRuleOnUpdate){
            throw 'Activator rule must remain stopped without historical application.'
        }
    }
    if(-not $ruleConfigured -and $rules.Count){throw 'An unapproved Activator rule exists.'}
    if(-not $ruleConfigured -and ($entities|ConvertTo-Json -Depth 60 -Compress) -match 'EmailMessage|TeamsMessage|FabricItemInvocation'){
        throw 'Unapproved delivery or invocation action exists in the Activator scaffold.'
    }
    $activatorStopped=$true
}
$ontology=Invoke-Fabric 'POST' "workspaces/$($state.workspaceId)/items/$($state.ontologyId)/getDefinition"
$ontologyParts=@($ontology.definition.parts)
if(@($ontologyParts|Where-Object path -match '^EntityTypes/[^/]+/definition.json$').Count -ne 6 -or
    @($ontologyParts|Where-Object path -match '^RelationshipTypes/[^/]+/definition.json$').Count -ne 6 -or
    @($ontologyParts|Where-Object path -match '/Contextualizations/').Count -ne 6){
    throw 'Ontology export is missing expected entity types, relationships or contextualizations.'
}
$timeSeries=@($ontologyParts|Where-Object path -match '/DataBindings/'|ForEach-Object{
    $binding=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_.payload))|ConvertFrom-Json
    if($binding.dataBindingConfiguration.dataBindingType -eq 'TimeSeries'){$binding.dataBindingConfiguration.sourceTableProperties}
})
if($timeSeries.Count -ne 1 -or $timeSeries[0].sourceType -ne 'KustoTable' -or
    $timeSeries[0].itemId -ne $state.eventhouseId -or $timeSeries[0].workspaceId -ne $state.workspaceId -or
    $timeSeries[0].databaseName -ne $state.databaseName -or $timeSeries[0].sourceTableName -ne 'Telemetry'){
    throw 'Ontology time-series source does not match the demo Eventhouse and physical Telemetry table.'
}
$fixtureRows=@()
$functionContracts=@()
if($Fixture){
    $result=Invoke-Kql (Get-Content -LiteralPath (Join-Path $script:Root 'kql\07-fixture-assertions.kql') -Raw)
    $fixtureRows=@($result.Tables[0].Rows|ForEach-Object{
        [pscustomobject]@{Check=$_[0];Expected=$_[1];Actual=$_[2];Passed=$_[3]}
    })
    $fixtureRows|Format-Table|Out-Host
    if($fixtureRows.Count -ne 15 -or @($fixtureRows|Where-Object {-not $_.Passed}).Count){
        throw 'Fixed-corpus KQL acceptance failed. Do not reload the corpus into a nonempty database.'
    }
    $contracts=Invoke-Kql (Get-Content -LiteralPath (Join-Path $script:Root 'kql\09-function-contract-assertions.kql') -Raw)
    $functionContracts=@($contracts.Tables[0].Rows|ForEach-Object{
        [pscustomobject]@{Check=$_[0];Passed=$_[1]}
    })
    $functionContracts|Format-Table|Out-Host
    if($functionContracts.Count -ne 3 -or @($functionContracts|Where-Object {-not $_.Passed}).Count){
        throw 'Actual as-of metadata or exact freshness-boundary function contract failed.'
    }
}
$topology=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/eventstreams/$($state.eventstreamId)/topology"
$graphPath=Join-Path $script:Root 'local-only\ontology-evidence.json'
$graph=$null
if(Test-Path -LiteralPath $graphPath){$graph=Get-Content -LiteralPath $graphPath -Raw|ConvertFrom-Json}
$graphVerified=($null -ne $graph -and $graph.ontologyId -eq $state.ontologyId -and
    $graph.graphModelId -eq $state.graphModelId -and $graph.relationships -eq 24 -and
    @($graph.nativeTraversal).Count -eq 1 -and $graph.graphToKqlCompoundKeyJoinVerified)
$agentEvaluations=@(Get-ChildItem -LiteralPath (Join-Path $script:Root 'local-only') -Filter 'agent-evaluation-*.json'|ForEach-Object{
    $evaluation=Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json
    if($evaluation.agentId -eq $state.dataAgentId -and $evaluation.PSObject.Properties['acceptanceCase'] -and
        $evaluation.acceptanceCase -in 'HighCount','GraphPath','CurrentStale','SiteInventory','CompareHistorical','AmbiguousAsset' -and
        [DateTimeOffset]$evaluation.observedAtUtc -ge [DateTimeOffset]$state.agentPublishedAtUtc){
        [pscustomobject]@{case=$evaluation.acceptanceCase;observedAtUtc=$evaluation.observedAtUtc;file=$_.Name;passed=$evaluation.semanticAcceptanceVerified}
    }
})
$agentChecks=@($agentEvaluations|Where-Object passed)
$agentVerified=@($agentChecks|Select-Object -ExpandProperty case -Unique).Count -eq 6
$kqlAgentVerified=@($agentChecks|Where-Object case -in 'HighCount','CurrentStale','SiteInventory','CompareHistorical','AmbiguousAsset'|Select-Object -ExpandProperty case -Unique).Count -eq 5
$evidence=[ordered]@{
    observedAtUtc=[DateTime]::UtcNow.ToString('o');workspaceId=$state.workspaceId;folderId=$state.folderId
    folderItems=@($items|Select-Object id,displayName,type,folderId)
    verifiedPrimaryItemCount=$expected.Count;agentPublishedSourceReferencesVerified=$true
    registeredReferenceTables=$names;fixtureAssertions=$fixtureRows
    functionContractAssertions=$functionContracts
    agentDraftKqlSourceVerified=$true;ontologyDefinitionSourceVerified=$true
    agentCuratedSchemaSelectionVerified=$true;agentNativeOntologyConfigured=$true
    agentOntologyBackingGraphConfigured=$graphAgentConfigured
    ontologyTraversalVerified=$graphVerified;ontologyRuntimeEvidence=$graph
    agentConversationVerified=$agentVerified;agentSemanticChecks=$agentChecks
    agentFailedSemanticChecks=@($agentEvaluations|Where-Object {-not $_.passed})
    agentKqlConversationVerified=$kqlAgentVerified
    activatorStopped=$activatorStopped;activatorRuleConfigured=$ruleConfigured
    liveStreamingVerified=$false;notificationDeliveryVerified=$false
    eventstreamTopology=$topology
}
$evidence|ConvertTo-Json -Depth 40|Set-Content -LiteralPath (Join-Path $script:Root 'local-only\acceptance.json')
Write-Host 'Deployment structure and requested fixed-corpus checks passed. Inspect saved runtime verdicts; structure passing does not imply end-to-end readiness.'
