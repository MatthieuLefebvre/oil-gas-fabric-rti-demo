[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$s=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$base="workspaces/$($s.workspaceId)/dataAgents/$($s.dataAgentId)/staging/datasources/$($s.databaseId)"
$source=Invoke-Fabric 'GET' $base
if($source.itemReference.itemId -ne $s.databaseId -or $source.itemReference.workspaceId -ne $s.workspaceId){
    throw 'Unexpected KQL source reference.'
}
if(-not $PSCmdlet.ShouldProcess('OilGasOperationsAgent','Select only curated operational functions and three reference tables')){return}
$roots=@(Get-FabricCollection "$base/elements")
$allowedFunctions=@([regex]::Matches(
    (Get-Content -LiteralPath (Join-Path $script:Root 'kql\03-functions.kql') -Raw),
    '\)\s+([A-Za-z]+)\('
)|ForEach-Object {$_.Groups[1].Value})
if($allowedFunctions.Count -ne 11){throw 'Expected eleven curated operational functions.'}
$selected=[Collections.Generic.List[object]]::new()
foreach($group in @(
    @{Type='Functions';Names=$allowedFunctions},
    @{Type='Tables';Names=@('AssetRegistry','MeasurementRegistry','AssetRelationships')}
)){
    $schemaRoot=@($roots|Where-Object type -eq $group.Type)
    if($schemaRoot.Count -ne 1){throw "Missing schema catalog: $($group.Type)"}
    $elements=@(Get-FabricCollection ("$base/elements?rootId="+[uri]::EscapeDataString($schemaRoot[0].id)))
    foreach($name in $group.Names){
        if(@($elements|Where-Object displayName -eq $name).Count -ne 1){throw "Missing source element: $name"}
    }
    foreach($element in $elements){
        $shouldSelect=$element.displayName -in $group.Names
        if($element.isSelected -ne $shouldSelect){
            Invoke-Fabric 'PATCH' ("$base/elements?id="+[uri]::EscapeDataString($element.id)) @{isSelected=$shouldSelect}|Out-Null
        }
        if($shouldSelect){$selected.Add([pscustomobject]@{name=$element.displayName;type=$element.type;id=$element.id})}
    }
    $verified=@(Get-FabricCollection ("$base/elements?rootId="+[uri]::EscapeDataString($schemaRoot[0].id)))
    if(@($verified|Where-Object isSelected).Count -ne $group.Names.Count){throw "Source selection did not persist: $($group.Type)"}
}
$source=Invoke-Fabric 'GET' $base
if($source.selectionState -notin 'All','Partial'){throw 'Selected source is not available to the agent.'}
$graphSelection=$null
if($s.PSObject.Properties['dataAgentGraphConfigured'] -and $s.dataAgentGraphConfigured){
    $graphBase="workspaces/$($s.workspaceId)/dataAgents/$($s.dataAgentId)/staging/datasources/$($s.graphModelId)"
    $graphSource=Invoke-Fabric 'GET' $graphBase
    if($graphSource.itemReference.itemId -ne $s.graphModelId -or $graphSource.itemReference.workspaceId -ne $s.workspaceId){
        throw 'Unexpected ontology backing graph source.'
    }
    $graphElements=@(Get-FabricCollection "$graphBase/elements")
    if($graphElements.Count -ne 12 -or @($graphElements|Where-Object type -eq 'NodeType').Count -ne 6 -or
        @($graphElements|Where-Object type -eq 'EdgeType').Count -ne 6){throw 'Unexpected graph schema: expected six node and six edge types.'}
    foreach($element in $graphElements){
        if(-not $element.isSelected){
            Invoke-Fabric 'PATCH' ("$graphBase/elements?id="+[uri]::EscapeDataString($element.id)) @{isSelected=$true}|Out-Null
        }
    }
    $verifiedGraph=@(Get-FabricCollection "$graphBase/elements")
    if(@($verifiedGraph|Where-Object isSelected).Count -ne 12){throw 'Graph source selection did not persist.'}
    $graphSelection=@{sourceId=$s.graphModelId;selected=@($verifiedGraph|Select-Object id,displayName,type,isSelected)}
}
@{observedAtUtc=[DateTime]::UtcNow.ToString('o');sourceId=$s.databaseId;selectionState=$source.selectionState;selected=$selected.ToArray();graphSource=$graphSelection}|
    ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $script:Root 'local-only\agent-selection.json')
Write-Host 'Eleven curated functions and three reference tables selected; raw tables and internal normalizer remain unselected.'
