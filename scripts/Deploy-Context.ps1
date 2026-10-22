[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if(-not $PSCmdlet.ShouldProcess($script:Config.folderPath,'Deploy documented JSON ontology with static and Eventhouse time-series bindings')){return}
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$parts=[Collections.Generic.List[object]]::new()
$parts.Add((New-Part 'definition.json' '{}'))
$parts.Add((New-Part '.platform' (@{metadata=@{type='Ontology';displayName='OilGasOperationalOntology'}}|ConvertTo-Json -Depth 5)))
$types='Site','Battery','System','Compressor','Component','Measurement'
$typeIds=@{};$propertyIds=@{};$entitySpecs=@()
for($index=0;$index -lt $types.Count;$index++){
    $type=$types[$index];$id=[string](100001+$index);$typeIds[$type]=$id
    $names=if($type -eq 'Measurement'){'MeasurementId','AssetId','ComponentId','SiteId','Source','UnitNum','Name','DisplayName','EngineeringUnit','Metric'}else{'EntityId','DisplayName','ParentId','SiteId','AssetId'}
    $properties=@();$mapping=@{};$propertyIndex=0
    foreach($name in $names){
        $propertyId=[string](10000000+($index+1)*1000+(++$propertyIndex));$mapping[$name]=$propertyId
        $properties+=@{id=$propertyId;name=$name;valueType='String'}
    }
    $propertyIds[$type]=$mapping
    $keys=if($type -eq 'Measurement'){@($mapping.Source,$mapping.UnitNum,$mapping.Name)}else{@($mapping.EntityId)}
    $entity=@{id=$id;namespace='usertypes';namespaceType='Custom';visibility='Visible';name=$type
        entityIdParts=@($keys);displayNamePropertyId=$mapping.DisplayName;properties=$properties
        semanticEnrichment=@{description="Synthetic oil-and-gas $type. Preview JSON experience; migrate before its January 31, 2027 retirement."}}
    $bindings=@($names|ForEach-Object{@{sourceColumnName=$_;targetPropertyId=$mapping[$_]}})
    if($type -eq 'Measurement'){
        $tp=@();$tsBindings=@()
        foreach($field in @(@('EventTime','DateTime'),@('NumericValue','Double'),@('EventhouseIngestedAt','DateTime'))){
            $propertyId=[string](10000000+($index+1)*1000+(++$propertyIndex))
            $tp+=@{id=$propertyId;name=$field[0];valueType=$field[1]}
            $tsBindings+=@{sourceColumnName=$field[0];targetPropertyId=$propertyId}
        }
        foreach($name in 'Source','UnitNum','Name'){$tsBindings+=@{sourceColumnName=$name;targetPropertyId=$mapping[$name]}}
        $entity.timeseriesProperties=$tp
        $bindingId="415ad7d6-e9d1-4dc5-a3d2-$('{0:d12}' -f ($index+1))"
        $binding=@{id=$bindingId;dataBindingConfiguration=[ordered]@{dataBindingType='TimeSeries';timestampColumnName='EventTime';propertyBindings=$tsBindings
            sourceTableProperties=[ordered]@{sourceType='KustoTable';workspaceId=$s.workspaceId;itemId=$s.eventhouseId;clusterUri=$s.queryServiceUri;databaseName=$s.databaseName;sourceTableName='Telemetry'}}}
        $parts.Add((New-Part "EntityTypes/$id/DataBindings/$bindingId.json" ($binding|ConvertTo-Json -Depth 30)))
    }
    $parts.Add((New-Part "EntityTypes/$id/definition.json" ($entity|ConvertTo-Json -Depth 30)))
    $bindingId="566c75cc-7b82-43d8-b8ec-$('{0:d12}' -f ($index+1))"
    $binding=@{id=$bindingId;dataBindingConfiguration=[ordered]@{dataBindingType='NonTimeSeries';propertyBindings=$bindings
        sourceTableProperties=[ordered]@{sourceType='LakehouseTable';workspaceId=$s.workspaceId;itemId=$s.lakehouseId;sourceTableName=$type}}}
    $parts.Add((New-Part "EntityTypes/$id/DataBindings/$bindingId.json" ($binding|ConvertTo-Json -Depth 30)))
    $entitySpecs+=@{type=$type;id=$id;keyProperties=$keys;sourceTable=$type}
}
$pairs=@(@('Site','Battery'),@('Battery','System'),@('System','Compressor'),@('Compressor','Component'),@('Compressor','Measurement'),@('Component','Measurement'))
for($i=0;$i -lt $pairs.Count;$i++){
    $from=$pairs[$i][0];$to=$pairs[$i][1];$id=[string](200001+$i)
    $relationship=@{id=$id;namespace='usertypes';namespaceType='Custom';name="${from}_contains_${to}"
        source=@{entityTypeId=$typeIds[$from]};target=@{entityTypeId=$typeIds[$to]}}
    $parts.Add((New-Part "RelationshipTypes/$id/definition.json" ($relationship|ConvertTo-Json -Depth 10)))
    $targetBindings=if($to -eq 'Measurement'){@('Source','UnitNum','Name')|ForEach-Object{@{sourceColumnName="Target$_";targetPropertyId=$propertyIds[$to][$_]}}}else{@{sourceColumnName='TargetId';targetPropertyId=$propertyIds[$to].EntityId}}
    $bindingId="f0417b25-6e83-4e2c-847d-$('{0:d12}' -f ($i+1))"
    $context=@{id=$bindingId;dataBindingTable=[ordered]@{sourceType='LakehouseTable';workspaceId=$s.workspaceId;itemId=$s.lakehouseId;sourceTableName="Edge_${from}_${to}"}
        sourceKeyRefBindings=@(@{sourceColumnName='SourceId';targetPropertyId=$propertyIds[$from].EntityId})
        targetKeyRefBindings=@($targetBindings)}
    $parts.Add((New-Part "RelationshipTypes/$id/Contextualizations/$bindingId.json" ($context|ConvertTo-Json -Depth 20)))
}
New-Item -ItemType Directory -Path (Join-Path $script:Root 'ontology') -Force|Out-Null
@{experience='JSON (old), documented and supported until 2027-01-31; migration required';entities=$entitySpecs;definition=@{parts=$parts.ToArray()}}|
    ConvertTo-Json -Depth 100|Set-Content -LiteralPath (Join-Path $script:Root 'ontology\definition.json')
$ontology=Set-DemoItem 'OilGasOperationalOntology' 'Ontology' $parts.ToArray()
$s.ontologyId=$ontology.id
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
