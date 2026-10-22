[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(1,100)][int]$BatchSize=12,
    [ValidateRange(1,1080)][int]$Batches=1,
    [ValidateRange(1,60)][int]$IntervalSeconds=10,
    [switch]$Scenario,
    [string]$PythonExecutable='python'
)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
if(-not $PSCmdlet.ShouldProcess($script:Config.folderPath,'Append fresh synthetic telemetry directly to Eventhouse; no Eventstream publishing')){
    return
}
Assert-Target
$state=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$database=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/items/$($state.databaseId)"
if($database.type -ne 'KQLDatabase' -or $database.folderId -ne $script:Config.folderId -or
    $database.displayName -ne $state.databaseName){
    throw 'Direct-ingestion database does not match the approved folder and database name.'
}
$runId=[guid]::NewGuid().ToString('N')
$directory=Join-Path $script:Root "local-only\direct-ingestion-$runId"
$evidencePath=Join-Path $script:Root "local-only\direct-ingestion-evidence-$runId.json"
$started=[DateTimeOffset]::UtcNow
$scheduledSeconds=if($Batches -gt 1){$Batches*$IntervalSeconds}else{0}
$summary=[ordered]@{
    runId=$runId;workspaceId=$state.workspaceId;databaseId=$state.databaseId;table='RawTelemetry'
    status='Running';stage='Generate';requestedRows=$BatchSize*$Batches
    attemptedRows=0;acknowledgedRows=0;verifiedRawRows=0;completedBatches=0;ingestedExtentIds=@()
    eventstreamUsed=$false;streamingIngestionApiUsed=$false
    startedAtUtc=$started.ToString('o')
    scheduledDurationSeconds=$scheduledSeconds
    scheduledCompletionUtc=$started.AddSeconds($scheduledSeconds).ToString('o')
}
$clock=[Diagnostics.Stopwatch]::StartNew()
Write-Host "Direct-ingestion progress: $evidencePath"
Push-Location $script:Root
try {
    $start=[DateTimeOffset]::UtcNow.AddSeconds(-$IntervalSeconds).ToString("yyyy-MM-dd'T'HH:mm:ss.ffffff'Z'",[Globalization.CultureInfo]::InvariantCulture)
    $rate=([double]$BatchSize/$IntervalSeconds).ToString('R',[Globalization.CultureInfo]::InvariantCulture)
    $arguments=@('-m','simulator.telemetry','generate','--output',$directory,
        '--count',"$($summary.requestedRows)",'--rate',$rate,'--start',$start)
    if($Scenario){$arguments+='--scenario'}
    $output=@(& $PythonExecutable @arguments 2>&1)
    if($LASTEXITCODE -ne 0){
        $output|Write-Host
        throw 'Synthetic generation failed; no batch ingestion was attempted.'
    }
    $records=@(Get-Content -LiteralPath (Join-Path $directory 'telemetry.ndjson'))
    if($records.Count -ne $summary.requestedRows){throw 'Generated row count does not match the requested run.'}
    for($batch=0;$batch -lt $Batches;$batch++){
        $first=$batch*$BatchSize
        $last=$first+$BatchSize-1
        $lines=@($records[$first..$last])
        $summary.stage='Ingest'
        $summary.attemptedRows+=$lines.Count
        $command=".ingest inline into table RawTelemetry with (format='multijson',ingestionMappingReference='TelemetryJson') <|`n"+($lines -join "`n")
        $response=Invoke-Kql $command -Management
        $extents=@(Get-KqlIngestionExtentIds $response)
        $summary.ingestedExtentIds+=$extents
        $summary.acknowledgedRows+=$lines.Count
        $summary.stage='Verify'
        $extentLiterals=@($extents|ForEach-Object {"guid('$_')"})
        $receipt=Invoke-Kql "RawTelemetry | where extent_id() in ($($extentLiterals -join ',')) | count"
        if(@($receipt.Tables).Count -lt 1 -or @($receipt.Tables[0].Rows).Count -ne 1 -or
            [long]$receipt.Tables[0].Rows[0][0] -ne $lines.Count){
            throw 'Raw extent receipt does not match the generated batch. Stop and investigate; do not blindly replay.'
        }
        $summary.verifiedRawRows+=$lines.Count
        $summary.completedBatches++
        $summary.updatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        $summary.elapsedSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,3)
        $summary|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $evidencePath
        Write-Host "Direct Eventhouse batch $($batch+1)/${Batches}: $($lines.Count) raw rows verified."
        if($Batches -gt 1){
            $delay=($batch+1)*$IntervalSeconds-$clock.Elapsed.TotalSeconds
            if($delay -gt 0){Start-Sleep -Milliseconds ([int][Math]::Ceiling($delay*1000))}
        }
    }
    $summary.stage='Completed'
    $summary.status='Succeeded'
} finally {
    Pop-Location
    if($summary.status -ne 'Succeeded'){$summary.status='Failed'}
    $summary.completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
    $summary.elapsedSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,3)
    $summary|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $evidencePath
    foreach($name in 'telemetry.ndjson','manifest.json'){
        $path=Join-Path $directory $name
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
    }
    if(Test-Path -LiteralPath $directory){Remove-Item -LiteralPath $directory}
    $summary|ConvertTo-Json -Depth 10|Write-Host
    Write-Host "Direct-ingestion evidence: $evidencePath"
}
