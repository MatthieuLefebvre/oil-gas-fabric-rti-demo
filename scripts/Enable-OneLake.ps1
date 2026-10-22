[CmdletBinding(SupportsShouldProcess)]
param([switch]$Backfill)
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
if (-not $PSCmdlet.ShouldProcess('OilGasOperationsDB.Telemetry', 'Enable OneLake availability at a five-minute target latency')) { return }
$result = Invoke-Kql '.show table Telemetry policy mirroring' -Management
$policy = $result.Tables[0].Rows[0][2] | ConvertFrom-Json
if ($Backfill -and $policy.IsEnabled -and -not $policy.Backfill) {
    Write-Warning 'Restarting only this demo table mirroring policy to include its existing rows. This does not delete Eventhouse telemetry.'
    Invoke-Kql '.alter-merge table Telemetry policy mirroring dataformat=parquet with (IsEnabled=false)' -Management | Out-Null
}
$properties = if ($Backfill -and -not $policy.Backfill) {
    'IsEnabled=true, Backfill=true, TargetLatencyInMinutes=5'
} else { 'IsEnabled=true, TargetLatencyInMinutes=5' }
Invoke-Kql ".alter-merge table Telemetry policy mirroring dataformat=parquet with ($properties)" -Management | Out-Null
Write-Host 'Policy enabled. A policy is not proof of completed Delta export; inspect mirroring statistics and read OneLake.'
