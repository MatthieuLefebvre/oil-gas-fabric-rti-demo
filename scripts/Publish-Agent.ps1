[CmdletBinding(SupportsShouldProcess)]
param()
. (Join-Path $PSScriptRoot 'Fabric.Client.ps1')
Assert-Target
$stateFile=Join-Path $script:Root 'local-only\deployment.json'
$s=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -AsHashtable
$item=Invoke-Fabric 'GET' "workspaces/$($s.workspaceId)/items/$($s.dataAgentId)"
if($item.type -ne 'DataAgent' -or $item.folderId -ne $s.folderId){throw 'Agent is not in the approved folder.'}
if(-not $PSCmdlet.ShouldProcess($item.displayName,'Publish read-only synthetic agent for bounded runtime evaluation; no permission/sharing changes')){return}
$source=Invoke-Fabric 'GET' "workspaces/$($s.workspaceId)/dataAgents/$($s.dataAgentId)/staging/datasources/$($s.databaseId)"
if($source.selectionState -notin 'All','Partial'){throw 'Cannot publish an agent with no selected KQL schema. Run Select-AgentSources.ps1.'}
if($s.ContainsKey('dataAgentGraphConfigured') -and $s.dataAgentGraphConfigured){
    $graph=Invoke-Fabric 'GET' "workspaces/$($s.workspaceId)/dataAgents/$($s.dataAgentId)/staging/datasources/$($s.graphModelId)"
    if($graph.selectionState -notin 'Selected','All','Partial'){throw 'Cannot publish an unselected graph datasource.'}
}
Invoke-Fabric 'POST' "workspaces/$($s.workspaceId)/dataAgents/$($s.dataAgentId)/staging/publish" @{
    publishedDescription='Synthetic oil-and-gas operational demo. Historical fixture; preview ontology. Not production or equipment control.'
}|Out-Null
$s.agentPublishedAtUtc=[DateTime]::UtcNow.ToString('o')
$s|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $stateFile
Write-Host 'Demo agent published within its existing permissions. Actual conversational correctness must be evaluated separately.'
