[CmdletBinding(SupportsShouldProcess)]
param([string]$Recipient)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if($Recipient){$null=[Net.Mail.MailAddress]::new($Recipient)}
if(-not $PSCmdlet.ShouldProcess($script:Config.folderPath,'Deploy stopped Activator source/object; add a stopped rule only when an explicit recipient is supplied')){return}
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$ids=@{}
$names='container','source','event','object','identityPart','identityTuple','split','pressure','rule'
for($i=0;$i -lt $names.Count;$i++){$ids[$names[$i]]="a50c0e75-1e33-479e-8324-$('{0:d12}' -f ($i+1))"}
$entities=[Collections.Generic.List[object]]::new()
$script:ActivatorStep=0
function Argument([string]$Name,[string]$Type,$Value){@{name=$Name;type=$Type;value=$Value}}
function Reference([string]$Name,[string]$Kind,[string]$Id){
    @{name=$Name;kind=$Kind;type='complex';arguments=@((Argument 'entityId' 'string' $Id))}
}
function Row([string]$Name,[string]$Kind,[array]$Arguments){@{name=$Name;kind=$Kind;arguments=$Arguments}}
function Step([string]$Name,[array]$Rows){
    $script:ActivatorStep++
    @{name=$Name;id="73c71a3a-a08e-4cf1-9d35-$('{0:d12}' -f $script:ActivatorStep)";rows=$Rows}
}
function Instance([string]$Template,[array]$Steps,[string]$Version='1.1'){
    @{templateId=$Template;templateVersion=$Version;steps=$Steps}|ConvertTo-Json -Depth 40 -Compress
}
function Add-View([string]$Key,[string]$Name,[hashtable]$Definition,[switch]$ObjectScoped){
    $payload=@{name=$Name;parentContainer=@{targetUniqueIdentifier=$ids.container};definition=$Definition}
    if($ObjectScoped){$payload.parentObject=@{targetUniqueIdentifier=$ids.object}}
    $entities.Add(@{uniqueIdentifier=$ids[$Key];type='timeSeriesView-v1';payload=$payload})
}
$entities.Add(@{uniqueIdentifier=$ids.container;type='container-v1';payload=@{name='Synthetic OilGas pressure draft';type='kqlQueries'}})
$query=(Get-Content -LiteralPath (Join-Path $script:Root 'kql\08-activator-input.kql') -Raw).
    Replace('LatestCompressorMeasurements()', "database('$($s.databaseName)').LatestCompressorMeasurements()")
$entities.Add(@{uniqueIdentifier=$ids.source;type='kqlSource-v1';payload=@{
    name='Fresh synthetic discharge pressure (stopped)';runSettings=@{isStopped=$true;executionIntervalInSeconds=60}
    query=@{queryString=$query};parentContainer=@{targetUniqueIdentifier=$ids.container}
    eventhouseItem=@{workspaceId=$s.workspaceId;itemId=$s.databaseId;itemType='KustoDatabase'}
}})
$sourceSteps=@((Step 'SourceEventStep' @((Row 'SourceSelector' 'SourceReference' @((Argument 'entityId' 'string' $ids.source))))))
Add-View 'event' 'Fresh pressure observations' @{type='Event';instance=(Instance 'SourceEvent' $sourceSteps)}
Add-View 'object' 'Synthetic scoped pressure measurement' @{type='Object'}
$typeSteps=@((Step 'IdPartStep' @((Row 'TypeAssertion' 'TypeAssertion' @(
    (Argument 'op' 'string' 'Text'),(Argument 'format' 'string' '')
)))))
Add-View 'identityPart' 'MeasurementId' @{type='Attribute';instance=(Instance 'IdentityPartAttribute' $typeSteps)} -ObjectScoped
$tupleSteps=@((Step 'IdStructureStep' @((Row 'IdPart' 'IdPart' @((Reference 'idPart' 'AttributeReference' $ids.identityPart))))))
Add-View 'identityTuple' 'Measurement identity' @{type='Attribute';instance=(Instance 'IdentityTupleAttribute' $tupleSteps '1.3.0')} -ObjectScoped
$splitSteps=@((Step 'SplitEventStep' @(
    (Row 'EventSelector' 'Event' @((Reference 'event' 'EventReference' $ids.event))),
    (Row 'FieldIdMapping' 'FieldIdMapping' @((Argument 'fieldName' 'string' 'MeasurementId'),(Reference 'idPart' 'AttributeReference' $ids.identityPart))),
    (Row 'SplitEventOptions' 'EventOptions' @((Argument 'isAuthoritative' 'boolean' $false)))
)))
Add-View 'split' 'Pressure by measurement' @{type='Event';instance=(Instance 'SplitEvent' $splitSteps '1.3.0')} -ObjectScoped
$attributeSteps=@(
    (Step 'EventSelectStep' @(
        (Row 'EventSelector' 'Event' @((Reference 'event' 'EventReference' $ids.split))),
        (Row 'EventFieldSelector' 'EventField' @((Argument 'fieldName' 'string' 'NumericValue')))
    )),
    (Step 'EventComputeStep' @((Row 'TypeAssertion' 'TypeAssertion' @(
        (Argument 'op' 'string' 'Number'),(Argument 'format' 'string' '')
    ))))
)
Add-View 'pressure' 'Discharge pressure (psi)' @{type='Attribute';instance=(Instance 'BasicEventAttribute' $attributeSteps)} -ObjectScoped
if($Recipient){
    $action=Row 'EmailBinding' 'EmailMessage' @(
        (Argument 'messageLocale' 'string' 'en-us'),
        @{name='sentTo';type='array';values=@(@{type='string';value=$Recipient})},
        (Argument 'subject' 'string' 'Synthetic SITE-A CMP-A1 discharge pressure above 140 psi'),
        (Argument 'headline' 'string' 'Synthetic demonstration only. Review the scoped pressure observation and its event time in OilGasOperationsDashboard; no equipment action is authorized.')
    )
    $ruleSteps=@(
    (Step 'ScalarSelectStep' @((Row 'AttributeSelector' 'Attribute' @((Reference 'attribute' 'AttributeReference' $ids.pressure))))),
    (Step 'ScalarDetectStep' @(
        (Row 'NumberBecomes' 'NumberBecomes' @((Argument 'op' 'string' 'BecomesGreaterThan'),(Argument 'value' 'number' 140))),
        (Row 'OccurrenceOption' 'EachTime' @())
    )),
        (Step 'ActStep' @($action))
    )
    Add-View 'rule' 'Synthetic DP above 140 psi (stopped)' @{
    type='Rule';instance=(Instance 'AttributeTrigger' $ruleSteps)
    settings=@{shouldRun=$false;shouldApplyRuleOnUpdate=$false}
    } -ObjectScoped
}
$json=ConvertTo-Json -InputObject $entities.ToArray() -Depth 60
New-Item -ItemType Directory -Path (Join-Path $script:Root 'fabric\activator') -Force|Out-Null
$json|Set-Content -LiteralPath (Join-Path $script:Root 'fabric\activator\ReflexEntities.json')
$item=Set-DemoItem 'OilGasPressureAlert' 'Reflex' @((New-Part 'ReflexEntities.json' $json))
$s.activatorId=$item.id
$s.activatorRuleConfigured=[bool]$Recipient
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
Write-Host 'Activator source/object deployed stopped. A rule is included only with an explicit recipient and remains stopped. Sustained/recovery/cooldown and delivery require validation before activation.'
