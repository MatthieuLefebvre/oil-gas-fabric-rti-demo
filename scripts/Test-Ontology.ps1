[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$graphName="OilGasOperationalOntology_graph_$($s.ontologyId.Replace('-',''))"
$graphs=@(Get-FabricCollection "workspaces/$($s.workspaceId)/items?rootFolderId=$($s.folderId)&recursive=false"|
    Where-Object {$_.displayName -eq $graphName -and $_.type -eq 'GraphModel' -and $_.folderId -eq $s.folderId})
if($graphs.Count -ne 1){throw 'Expected one ontology-owned backing graph in the approved folder.'}
$graphId=$graphs[0].id
function Invoke-Graph([string]$Query) {
    $base="workspaces/$($s.workspaceId)/graphModels/$graphId/executeQuery?beta=true"
    $path=$base
    $deadline=[DateTime]::UtcNow.AddMinutes(2)
    $rows=[Collections.Generic.List[object]]::new()
    do {
        if([DateTime]::UtcNow -gt $deadline){throw 'Native ontology graph query timed out.'}
        $response=Invoke-Fabric 'POST' $path @{query=$Query}
        if($response.status.code -notin '00000','02000' -or
            ($response.PSObject.Properties['additionalStatuses'] -and $response.additionalStatuses.Count)){
            throw "Native graph query did not complete cleanly: $($response.status|ConvertTo-Json -Depth 10 -Compress)"
        }
        foreach($row in $response.result.data){$rows.Add($row)}
        $token=if($response.result.PSObject.Properties['nextPage']){$response.result.nextPage}else{$null}
        if($token){
            $path=$base+'&continuationToken='+[uri]::EscapeDataString($token)
            Start-Sleep -Seconds 2
        }
    }while($token)
    return $rows.ToArray()
}
$counts=[ordered]@{}
foreach($type in @(
    @{Name='Site';Count=2},@{Name='Battery';Count=2},@{Name='System';Count=2},
    @{Name='Compressor';Count=4},@{Name='Component';Count=4},@{Name='Measurement';Count=12}
)){
    $r=@(Invoke-Graph "MATCH (n:$($type.Name)) RETURN count(n) AS EntityCount")
    if($r.Count -ne 1 -or [long]$r[0].EntityCount -ne $type.Count){throw "Native entity count failed: $($type.Name)"}
    $counts[$type.Name]=[long]$r[0].EntityCount
}
$edges=@(Invoke-Graph 'MATCH ()-[r]->() RETURN count(r) AS RelationshipCount')
if($edges.Count -ne 1 -or [long]$edges[0].RelationshipCount -ne 24){throw 'Expected 24 native ontology relationships.'}
$query=Get-Content -LiteralPath (Join-Path $script:Root 'ontology\site-a-pressure.gql') -Raw
$pathRows=@(Invoke-Graph $query)
if($pathRows.Count -ne 1 -or $pathRows[0].MeasurementId -ne 'MSR-A1-DP' -or
    $pathRows[0].EngineeringUnit -ne 'psi'){throw 'Native site-to-component-pressure traversal failed.'}
$m=$pathRows[0]
$source=([string]$m.Source).Replace("'","''")
$unit=([string]$m.UnitNum).Replace("'","''")
$name=([string]$m.Name).Replace("'","''")
$kql=@"
LatestCompressorMeasurements(datetime(2026-10-20T12:00:00Z),15m)
| where Source=='$source' and UnitNum=='$unit' and Name=='$name'
| project SiteId,AssetId,MeasurementId,NumericValue,EngineeringUnit,EventTime,IsStale
"@
$telemetry=Invoke-Kql $kql
if($telemetry.Tables[0].Rows.Count -ne 1 -or $telemetry.Tables[0].Rows[0][0] -ne 'SITE-A' -or
    $telemetry.Tables[0].Rows[0][1] -ne 'CMP-A1' -or $telemetry.Tables[0].Rows[0][6]){
    throw 'Native graph compound key did not resolve to one fresh historical pressure measurement.'
}
$evidence=[ordered]@{
    observedAtUtc=[DateTime]::UtcNow.ToString('o');workspaceId=$s.workspaceId;ontologyId=$s.ontologyId
    graphModelId=$graphId;entityCounts=$counts;relationships=24
    nativeTraversal=$pathRows;graphToKqlCompoundKeyJoinVerified=$true;ontologyTimeSeriesUiVerified=$false
    historicalTelemetry=@($telemetry.Tables[0].Rows)
}
$evidence|ConvertTo-Json -Depth 30|Set-Content -LiteralPath (Join-Path $script:Root 'local-only\ontology-evidence.json')
$s.graphModelId=$graphId
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
Write-Host 'Native ontology backing graph: six entity counts, 24 relationships, full component-pressure traversal and compound-key KQL join passed.'
