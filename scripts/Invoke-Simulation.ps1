[CmdletBinding()]
param(
    [ValidateRange(1,1000000)][int]$Count=3000,
    [ValidateRange(0.1,1000)][double]$Rate=10,
    [switch]$Scenario,
    [switch]$WaitForReady,
    [ValidateRange(1,60)][int]$ConnectionWaitMinutes=15
)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$state=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$connection=$null
$old=$env:TELEMETRY_EVENTHUB_CONNECTION_STRING
try {
    Push-Location $script:Root
    try {
        if($WaitForReady){
            $deadline=[DateTimeOffset]::UtcNow.AddMinutes($ConnectionWaitMinutes)
            do {
                $connection=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/eventstreams/$($state.eventstreamId)/sources/$($state.eventstreamSourceId)/connection"
                if($connection.type -ne 'CustomEndpoint'){throw 'Expected the explicitly labeled synthetic endpoint.'}
                $env:TELEMETRY_EVENTHUB_CONNECTION_STRING=$connection.accessKeys.primaryConnectionString
                $probeOutput=@(& python -m simulator.publish --transport eventhubs-rest --count 1 --rate 1 --concurrency 1 --retries 0 2>&1)
                $probeExit=$LASTEXITCODE
                $probeOutput|Write-Host
                $probe=($probeOutput -join "`n")|ConvertFrom-Json
                if($null -eq $probe){throw 'Readiness probe returned no publisher summary.'}
                if($probeExit -eq 0){
                    if($probe.Accepted -ne 1 -or $probe.Failed -ne 0){throw 'Readiness probe did not confirm one accepted event.'}
                    Write-Host 'Eventstream accepted the readiness event; starting the finite telemetry run.'
                    break
                }
                if(-not $probe.PSObject.Properties['FirstFailure'] -or $null -eq $probe.FirstFailure -or
                    $probe.FirstFailure.Code -ne 'EventHubsHttpError' -or $probe.FirstFailure.HttpStatus -ne 401){
                    throw 'Readiness probe failed for a reason other than pending HTTP 401; inspect the sanitized summary.'
                }
                $remaining=($deadline-[DateTimeOffset]::UtcNow).TotalSeconds
                if($remaining -le 0){throw 'Eventstream still returns HTTP 401 after the bounded connection wait; no telemetry run was started.'}
                Write-Warning "Eventstream HTTP 401: no probe accepted. Waiting for manual configuration; next check in at most 30 seconds. Deadline $($deadline.ToString('o'))."
                Start-Sleep -Seconds ([Math]::Min(30,[Math]::Ceiling($remaining)))
            } while($true)
        }
        $connection=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/eventstreams/$($state.eventstreamId)/sources/$($state.eventstreamSourceId)/connection"
        if($connection.type -ne 'CustomEndpoint'){throw 'Expected the explicitly labeled synthetic endpoint.'}
        $env:TELEMETRY_EVENTHUB_CONNECTION_STRING=$connection.accessKeys.primaryConnectionString
        $arguments=@('-m','simulator.publish','--transport','eventhubs-rest','--count',"$Count",'--rate',"$Rate",'--concurrency','4')
        if($Scenario){$arguments+='--scenario'}
        & python @arguments
        if($LASTEXITCODE -ne 0){throw 'Synthetic publishing failed; inspect the sanitized publisher summary.'}
    } finally { Pop-Location }
} finally {
    $env:TELEMETRY_EVENTHUB_CONNECTION_STRING=$old
    $connection=$null
}
