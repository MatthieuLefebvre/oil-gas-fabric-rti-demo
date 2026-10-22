[CmdletBinding(SupportsShouldProcess)]
param([switch]$IncludeFixture)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if (-not $PSCmdlet.ShouldProcess($script:Config.folderPath, 'Load synthetic reference data and optional one-time fixed fixture')) { return }
Assert-Target
$assets=Import-Csv -LiteralPath (Join-Path $script:Root 'data\assets.csv')
$measurements=Import-Csv -LiteralPath (Join-Path $script:Root 'data\measurements.csv')
$relationships=Import-Csv -LiteralPath (Join-Path $script:Root 'data\relationships.csv')
$byId=@{}
foreach($row in $assets) { $byId[$row.AssetId]=$row }
$assetRows=@($assets | ForEach-Object {
    $compressor=if($_.AssetType -eq 'Compressor'){$_.AssetId}elseif($_.AssetType -eq 'Component'){$_.ParentAssetId}else{''}
    [ordered]@{EntityId=$_.AssetId;EntityType=$_.AssetType;DisplayName=$_.DisplayName;ParentId=$_.ParentAssetId;SiteId=$_.SiteId;AssetId=$compressor}
})
$measurementRows=@($measurements | ForEach-Object {
    $owner=$byId[$_.AssetId]
    $component=if($owner.AssetType -eq 'Component'){$owner.AssetId}else{''}
    $compressor=if($component){$owner.ParentAssetId}else{$owner.AssetId}
    [ordered]@{MeasurementId=$_.MeasurementId;AssetId=$compressor;ComponentId=$component;SiteId=$owner.SiteId
        Source=$_.Source;UnitNum=$_.UnitNum;Name=$_.Name;DisplayName=$_.MeasurementType
        EngineeringUnit=$_.Unit;Metric=$_.MeasurementType;HighThreshold=$_.HighThreshold;RecoveryThreshold=$_.RecoveryThreshold}
})
$edgeRows=@($relationships | ForEach-Object { [ordered]@{Relationship=$_.RelationshipType;SourceId=$_.FromId;TargetId=$_.ToId} })
function Set-ReferenceTable([string]$Name,[string]$Schema,[array]$Rows) {
    $values=@($Rows | ForEach-Object {
        foreach($value in $_.Values) {
            if($value -eq '') { "''" } else { "'" + ([string]$value).Replace("'","''") + "'" }
        }
    })
    Invoke-Kql ".set-or-replace $Name <| datatable($Schema)[$($values -join ',')]" -Management | Out-Null
}
Set-ReferenceTable 'AssetRegistry' 'EntityId:string,EntityType:string,DisplayName:string,ParentId:string,SiteId:string,AssetId:string' $assetRows
$typedMeasurements=@($measurementRows | ForEach-Object { $_ })
$values=@($typedMeasurements | ForEach-Object {
    foreach($entry in $_.GetEnumerator()) {
        if($entry.Key -in 'HighThreshold','RecoveryThreshold') {
            if($entry.Value -eq '') { 'real(null)' } else { 'real('+$entry.Value+')' }
        } else { "'" + ([string]$entry.Value).Replace("'","''") + "'" }
    }
})
Invoke-Kql ".set-or-replace MeasurementRegistry <| datatable(MeasurementId:string,AssetId:string,ComponentId:string,SiteId:string,Source:string,UnitNum:string,Name:string,DisplayName:string,EngineeringUnit:string,Metric:string,HighThreshold:real,RecoveryThreshold:real)[$($values -join ',')]" -Management | Out-Null
Set-ReferenceTable 'AssetRelationships' 'Relationship:string,SourceId:string,TargetId:string' $edgeRows
Invoke-KqlFile (Join-Path $script:Root 'kql\01-normalization.kql')
if($IncludeFixture) {
    $existing=Invoke-Kql "RawTelemetry | where RecordDateTimeUTC startswith '2026-10-20T' or RecordDateTimeUTC startswith 'not-' | count"
    if([long]$existing.Tables[0].Rows[0][0] -gt 0) { throw 'Fixture-like data already exists. Refusing replay; run read-only validation instead.' }
    $fixture=Get-Content -LiteralPath (Join-Path $script:Root 'tests\fixtures\telemetry.ndjson') -Raw
    Invoke-Kql (".ingest inline into table RawTelemetry with (format='multijson',ingestionMappingReference='TelemetryJson') <|`n"+$fixture) -Management | Out-Null
}
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$state=Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -AsHashtable
$tables=[ordered]@{}
foreach($type in 'Site','Battery','System','Compressor','Component') {
    $tables[$type]=@($assetRows | Where-Object EntityType -eq $type)
}
$tables.Measurement=$measurementRows
$tables.Relationship=$edgeRows
$measurementById=@{}
foreach($measurement in $measurementRows){$measurementById[$measurement.MeasurementId]=$measurement}
foreach($edge in $edgeRows){
    $fromType=$byId[$edge.SourceId].AssetType
    $toType=if($measurementById.ContainsKey($edge.TargetId)){'Measurement'}else{$byId[$edge.TargetId].AssetType}
    $tableName="Edge_${fromType}_${toType}"
    if(-not $tables.Contains($tableName)){$tables[$tableName]=@()}
    $enriched=[ordered]@{SourceId=$edge.SourceId;TargetId=$edge.TargetId}
    if($toType -eq 'Measurement'){
        $m=$measurementById[$edge.TargetId]
        $enriched.TargetSource=$m.Source;$enriched.TargetUnitNum=$m.UnitNum;$enriched.TargetName=$m.Name
    }
    $tables[$tableName]+=$enriched
}
$snapshot=$tables|ConvertTo-Json -Depth 30 -Compress
$snapshot|Set-Content -LiteralPath (Join-Path $script:Root 'local-only\reference-tables.json')
$metadata=@{kernel_info=@{name='synapse_pyspark'};dependencies=@{lakehouse=@{default_lakehouse=$state.lakehouseId;default_lakehouse_name='OilGasReference';default_lakehouse_workspace_id=$state.workspaceId}}}|ConvertTo-Json -Depth 10 -Compress
$notebook=@"
# Fabric notebook source
# METADATA ********************
# META $metadata
# CELL ********************
import json
from pyspark.sql.types import StructType, StructField, StringType
tables = json.loads(r'''$snapshot''')
for name, rows in tables.items():
    schema = StructType([StructField(key, StringType(), True) for key in rows[0]])
    frame = spark.createDataFrame(rows, schema)
    frame.write.format("delta").mode("overwrite").option("overwriteSchema", "true").saveAsTable(name)
    print(name, frame.count())
"@
New-Item -ItemType Directory -Path (Join-Path $script:Root 'fabric\notebooks') -Force | Out-Null
$notebook|Set-Content -LiteralPath (Join-Path $script:Root 'fabric\notebooks\LoadReference.py')
$item=Set-DemoItem 'OilGasLoadReference' 'Notebook' @((New-Part 'notebook-content.py' $notebook)) 'fabricGitSource'
$state.referenceNotebookId=$item.id
$state|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
Write-Host 'Reference registry and static snapshot prepared. Materialize with scripts\materialize_reference.py (recommended), or run OilGasLoadReference in Fabric; do not run both writers concurrently.'
