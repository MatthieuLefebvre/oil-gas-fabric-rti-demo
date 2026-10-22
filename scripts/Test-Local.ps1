[CmdletBinding()]
param()
$root=Split-Path -Parent $PSScriptRoot
$files=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')
foreach($file in $files){
    $tokens=$null;$parseErrors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)|Out-Null
    if($parseErrors.Count){throw "$($file.Name): $($parseErrors.Message -join '; ')"}
}
$config=Get-Content -LiteralPath (Join-Path $root 'config.example.json') -Raw|ConvertFrom-Json
if($config.workspaceId -ne '21733624-95b6-4740-b892-d29ff7889aa4' -or
    $config.folderId -ne '975ffc5a-edee-4558-a62d-3a2bfe72110c' -or
    $null -ne $config.kafkaConnectionId -or $null -ne $config.notificationRecipient){throw 'Unexpected example target or active connection/recipient.'}
$previews=@('Deploy-Demo.ps1','Deploy-Experience.ps1','Load-Reference.ps1','Deploy-Context.ps1','Deploy-Agent.ps1','Deploy-PublisherNotebook.ps1','Deploy-Activator.ps1','Invoke-DirectIngestion.ps1')
foreach($name in $previews){
    & (Join-Path $PSScriptRoot $name) -WhatIf
}
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
$extent='8ce78b22-9cca-405c-a00e-4085575fa5d8'
$ingestion=[pscustomobject]@{Tables=@([pscustomobject]@{
    Columns=@([pscustomobject]@{ColumnName='ExtentId'});Rows=@(@($extent),@('30c3bbcb-cfd5-405f-a910-dfa66d016d94'))
})}
$extentIds=@(Get-KqlIngestionExtentIds $ingestion)
if($extentIds.Count -ne 2 -or $extentIds[0] -ne $extent){throw 'Valid inline ingestion acknowledgements rejected.'}
foreach($rows in @(@(),@(@([guid]::Empty.ToString())),@(@('invalid')), @(@($extent),@($extent)))){
    $invalid=[pscustomobject]@{Tables=@([pscustomobject]@{
        Columns=@([pscustomobject]@{ColumnName='ExtentId'});Rows=$rows
    })}
    $rejected=$false
    try{Get-KqlIngestionExtentIds $invalid|Out-Null}catch{
        if($_.Exception.Message -notlike 'Inline ingestion*'){throw}
        $rejected=$true
    }
    if(-not $rejected){throw 'Invalid inline ingestion acknowledgement accepted.'}
}
function Assert-Target {}
function Get-FabricCollection([string]$Path) {
    @(
        [pscustomobject]@{id='lakehouse';displayName='OilGasReference';type='Lakehouse';folderId=$script:Config.folderId}
        [pscustomobject]@{id='sql';displayName='OilGasReference';type='SQLEndpoint';folderId=$script:Config.folderId}
    )
}
function Invoke-Fabric { throw 'The local existing-item test must not make an API request.' }
$existing=Set-DemoItem 'OilGasReference' 'Lakehouse'
if($existing.id -ne 'lakehouse'){throw 'Lakehouse lookup did not distinguish its generated SQL endpoint.'}
foreach($case in @(
    @{State=@{};Requested='';Expected='ProcessedIngestion'},
    @{State=@{eventstreamIngestionMode='DirectIngestion'};Requested='';Expected='DirectIngestion'},
    @{State=@{eventstreamIngestionMode='ProcessedIngestion'};Requested='';Expected='ProcessedIngestion'},
    @{State=@{eventstreamIngestionMode='ProcessedIngestion'};Requested='DirectIngestion';Expected='DirectIngestion'},
    @{State=@{eventstreamIngestionMode='DirectIngestion'};Requested='ProcessedIngestion';Expected='ProcessedIngestion'}
)){
    if((Resolve-DemoIngestionMode $case.State $case.Requested) -ne $case.Expected){throw 'Eventstream deployment mode preservation failed.'}
}
$rejected=$false
try{Resolve-DemoIngestionMode @{eventstreamIngestionMode='Unknown'}|Out-Null}catch{
    if($_.Exception.Message -ne 'Unknown saved/requested Eventstream ingestion mode.'){throw}
    $rejected=$true
}
if(-not $rejected){throw 'Invalid saved Eventstream mode was silently accepted.'}
. (Join-Path $PSScriptRoot 'Agent.Acceptance.ps1')
function New-TestAnswer([string]$Csv,[string]$Text=''){
    $content=@([pscustomobject]@{type='resource';resource=[pscustomobject]@{mimeType='text/csv';text=$Csv}})
    if($Text){$content+=[pscustomobject]@{type='text';text=$Text}}
    [pscustomobject]@{content=$content}
}
$highCsv="EngineeringUnit,UniqueHighPressureReadings,ObservationWindowStart,ObservationWindowEnd`npsi,10,2026-10-20T11:00:00Z,2026-10-20T12:00:00Z"
if(-not (Test-AgentAnswer (New-TestAnswer $highCsv) 'HighCount')){throw 'Valid high-count answer rejected.'}
foreach($invalid in @(
    $highCsv.Replace('psi,10','psi,0'),$highCsv.Replace('psi,10','mm/s,10'),
    $highCsv.Replace('11:00:00','10:00:00'),$highCsv.Split("`n")[0]
)){
    if(Test-AgentAnswer (New-TestAnswer $invalid) 'HighCount'){throw 'Invalid high-count answer accepted.'}
}
$pathCsv="SiteId,BatteryId,SystemId,CompressorId,ComponentId,MeasurementId,Source,UnitNum,Name,EngineeringUnit`nSITE-A,BAT-A,SYS-A,CMP-A1,THR-A1,MSR-A1-DP,SyntheticSCADA,1,Fictional_Aspen/Tank_Battery/Gas_Lift/Compressors/Compressor_1/Performance/Throw_3/DisplayedDiscPress,psi"
if(-not (Test-AgentAnswer (New-TestAnswer $pathCsv) 'OntologyPath')){throw 'Valid ontology answer rejected.'}
if(Test-AgentAnswer (New-TestAnswer $pathCsv.Replace('SITE-A','SITE-B')) 'OntologyPath'){throw 'Cross-site ontology answer accepted.'}
if(Test-AgentAnswer (New-TestAnswer $pathCsv.Replace('DisplayedDiscPress','DisplayedSuctionPress')) 'OntologyPath'){throw 'Wrong compound key accepted.'}
if(-not (Test-AgentAnswer (New-TestAnswer $pathCsv) 'GraphPath')){throw 'Valid graph answer rejected.'}
$pathParts=$pathCsv.Split("`n")
$encodedValues=($pathParts[1].Split(',')|ForEach-Object {'"""'+$_+'"""'}) -join ','
if(Test-AgentAnswer (New-TestAnswer ($pathParts[0]+"`n"+$encodedValues)) 'GraphPath'){throw 'JSON-encoded graph scalars were accepted as canonical identifiers.'}
$asOf=[DateTimeOffset]::UtcNow.ToString('o')
$eventTime=[DateTimeOffset]::UtcNow.AddHours(-2).ToString('o')
$staleRows=foreach($asset in 'A1','A2','B1','B2'){
    foreach($metric in 'DP','SP','VB'){
        [pscustomobject]@{
            FreshCount='0';StaleCount='12';MissingCount='0';AsOfUtc=$asOf
            MeasurementId="MSR-$asset-$metric";EngineeringUnit=$(if($metric -eq 'VB'){'mm/s'}else{'psi'})
            EventTime=$eventTime;FreshnessStatus='Stale'
        }
    }
}
$staleCsv=($staleRows|ConvertTo-Csv -NoTypeInformation) -join "`n"
if(-not (Test-AgentAnswer (New-TestAnswer $staleCsv) 'CurrentStale')){throw 'Valid stale-now answer rejected.'}
foreach($invalid in @(
    $staleCsv.Replace('"0","12"','"1","12"'),$staleCsv.Replace('"mm/s"','"psi"'),
    $staleCsv.Replace($eventTime,''),$staleCsv.Replace($asOf,[DateTimeOffset]::UtcNow.AddDays(1).ToString('o')),
    $staleCsv.Replace($eventTime,[DateTimeOffset]::Parse($asOf).AddSeconds(-60).ToString('o'))
)){
    if(Test-AgentAnswer (New-TestAnswer $invalid) 'CurrentStale'){throw 'Invalid stale-now answer accepted.'}
}
$scopedRows=foreach($asset in 'A1','A2','B1'){
    foreach($metric in 'DP','SP','VB'){
        [pscustomobject]@{
            MeasurementId="MSR-$asset-$metric";AssetId="CMP-$asset";SiteId="SITE-$($asset.Substring(0,1))"
            Metric=$(@{DP='DischargePressure';SP='SuctionPressure';VB='Vibration'}[$metric])
            EngineeringUnit=$(if($metric -eq 'VB'){'mm/s'}else{'psi'})
            AsOfUtc=$asOf;EventTime=$eventTime;IsStale='1'
        }
    }
}
$inventory=@($scopedRows|Where-Object SiteId -eq 'SITE-A')
$inventoryCsv=($inventory|ConvertTo-Csv -NoTypeInformation) -join "`n"
if(-not (Test-AgentAnswer (New-TestAnswer $inventoryCsv) 'SiteInventory')){throw 'Valid site inventory rejected.'}
$duplicateInventory=(@($inventory[0],$inventory[0])+$inventory[2..5]|ConvertTo-Csv -NoTypeInformation) -join "`n"
foreach($invalid in @($inventoryCsv.Replace('SITE-A','SITE-B'),$inventoryCsv.Replace('mm/s','psi'),$duplicateInventory)){
    if(Test-AgentAnswer (New-TestAnswer $invalid) 'SiteInventory'){throw 'Invalid site inventory accepted.'}
}
$ambiguous=@($scopedRows|Where-Object AssetId -in 'CMP-A1','CMP-B1')
$ambiguousCsv=($ambiguous|ConvertTo-Csv -NoTypeInformation) -join "`n"
if(-not (Test-AgentAnswer (New-TestAnswer $ambiguousCsv 'This is not a diagnosis.') 'AmbiguousAsset')){throw 'Both-scoped-assets answer rejected.'}
$singleSiteCsv=($ambiguous|Where-Object SiteId -eq 'SITE-A'|ConvertTo-Csv -NoTypeInformation) -join "`n"
if(Test-AgentAnswer (New-TestAnswer $singleSiteCsv 'This is not a diagnosis.') 'AmbiguousAsset'){throw 'Ambiguous asset silently restricted to one site.'}
if(Test-AgentAnswer (New-TestAnswer $ambiguousCsv) 'AmbiguousAsset'){throw 'Missing diagnosis boundary accepted.'}
$comparison=@(foreach($asset in 'CMP-A1','CMP-B1'){
    foreach($metric in 'DischargePressure','SuctionPressure','Vibration'){
        [pscustomobject]@{
            AssetId=$asset;Metric=$metric;EngineeringUnit=$(if($metric -eq 'Vibration'){'mm/s'}else{'psi'})
            Average=40.125;Minimum=39.5;Maximum=45.125;Samples=10;LatestTime='2026-10-20T11:57:16Z'
            ObservationWindowStart='2026-10-20T11:00:00Z';ObservationWindowEnd='2026-10-20T12:00:00Z'
        }
    }
})
$comparisonCsv=($comparison|ConvertTo-Csv -NoTypeInformation) -join "`n"
if(-not (Test-AgentAnswer (New-TestAnswer $comparisonCsv) 'CompareHistorical' -ExpectedRows $comparison)){throw 'Exact KQL-grounded comparison rejected.'}
$duplicateComparison=(@($comparison[0],$comparison[0])+$comparison[2..5]|ConvertTo-Csv -NoTypeInformation) -join "`n"
foreach($invalid in @(
    $comparisonCsv.Replace('40.125','40.126'),$comparisonCsv.Replace('"10"','"11"'),
    $comparisonCsv.Replace('mm/s','psi'),$comparisonCsv.Replace('11:00:00','10:00:00'),$duplicateComparison
)){
    if(Test-AgentAnswer (New-TestAnswer $invalid) 'CompareHistorical' -ExpectedRows $comparison){throw 'Invalid KQL-grounded comparison accepted.'}
}
Push-Location $root
try {
    $probeOutput=@(& python -m simulator.publish --transport eventhubs-rest --count 1 --rate 0 --concurrency 1 --retries 0 2>&1)
    $probeExit=$LASTEXITCODE
    $probe=($probeOutput -join "`n")|ConvertFrom-Json
    if($probeExit -ne 1 -or $probe.FirstFailure.Code -ne 'InvalidConfiguration'){
        throw 'Native publisher stderr summary was not captured correctly.'
    }
    $start=[DateTimeOffset]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
    $generated=@(& python -m simulator.telemetry stdout --count 1 --rate 1000 --start $start)
    if($LASTEXITCODE -ne 0 -or $generated.Count -ne 1){throw 'Direct-ingestion timestamp is incompatible with the generator.'}
    $row=$generated[0]|ConvertFrom-Json
    if([DateTimeOffset]$row.RecordDateTimeUTC -ne [DateTimeOffset]$start){
        throw 'Direct-ingestion timestamp changed while passing through the shared generator.'
    }
    $scenarioCheck=@'
from simulator.telemetry import iter_live, parse_time
rows = list(iter_live(181, rate=1.2, scenario=True))
assert (parse_time(rows[12]["RecordDateTimeUTC"]) - parse_time(rows[0]["RecordDateTimeUTC"])).total_seconds() == 10
assert rows[0]["Name"] != rows[1]["Name"]
assert float(rows[0]["Value"]) < 140 < float(rows[60]["Value"])
assert float(rows[180]["Value"]) < 140
print("Direct micro-batch sequence, high and recovery scenario passed.")
'@
    & python -c $scenarioCheck
    if($LASTEXITCODE -ne 0){throw 'Direct micro-batch generator continuity failed.'}
} finally {Pop-Location}
Write-Host "$($files.Count) PowerShell files parse; configuration, $($previews.Count) no-write paths, Lakehouse lookup, inline extent acknowledgements, generator timestamp, publisher stderr capture, six ingestion-mode and twenty-nine agent acceptance cases passed."
