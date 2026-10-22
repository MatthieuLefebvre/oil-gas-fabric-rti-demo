[CmdletBinding()]
param([string]$NotebookStateKey='referenceNotebookId')
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$state=Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw|ConvertFrom-Json
$notebookId=$state.$NotebookStateKey
$item=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/items/$notebookId"
if($item.folderId -ne $script:Config.folderId -or $item.type -ne 'Notebook'){throw 'Notebook target mismatch.'}
$response=Invoke-WebRequest -Method Post -Uri "$script:FabricBase/workspaces/$($state.workspaceId)/items/$notebookId/jobs/RunNotebook/instances" `
    -Headers @{Authorization='Bearer '+(Get-AccessToken 'https://api.fabric.microsoft.com')} -ContentType 'application/json' -Body '{}'
$location=[string]@($response.Headers['Location'])[0]
if(-not $location){throw 'Notebook start returned no job location.'}
@{location=$location;notebookId=$notebookId;startedAtUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $script:Root "local-only\$NotebookStateKey-job-start.json")
$delay=if($response.Headers['Retry-After']){[int]@($response.Headers['Retry-After'])[0]}else{15}
$deadline=[DateTime]::UtcNow.AddMinutes(12)
do{
    if([DateTime]::UtcNow -gt $deadline){
        $jobId=([uri]$location).AbsolutePath.TrimEnd('/').Split('/')[-1]
        Invoke-Fabric 'POST' "workspaces/$($state.workspaceId)/items/$notebookId/jobs/instances/$jobId/cancel"|Out-Null
        throw "Notebook exceeded its bounded deadline and cancellation was requested: $jobId"
    }
    Start-Sleep -Seconds ([math]::Max(5,$delay))
    $job=Invoke-Fabric 'GET' $location
    Write-Host "Notebook job: $($job.status)"
}while($job.status -in 'NotStarted','InProgress','Running')
$job|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $script:Root "local-only\$NotebookStateKey-job.json")
if($job.status -ne 'Completed'){throw ($job|ConvertTo-Json -Depth 15)}
$jobId=([uri]$location).AbsolutePath.TrimEnd('/').Split('/')[-1]
$details=Invoke-Fabric 'GET' "workspaces/$($state.workspaceId)/notebooks/$notebookId/jobs/execute/instances/$($jobId)?beta=true"
$details|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $script:Root "local-only\$NotebookStateKey-job-details.json")
if($details.properties.exitValue){
    $exitValue=$details.properties.exitValue
    Write-Host "Notebook exit value: $exitValue"
    if($exitValue.StartsWith('{')){
        $result=$exitValue|ConvertFrom-Json
        if($result.PSObject.Properties['status'] -and $result.status -eq 'Failed'){
            throw "Notebook reported a failed operation: $exitValue"
        }
    }
}
