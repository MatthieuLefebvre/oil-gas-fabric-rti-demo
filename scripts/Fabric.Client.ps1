Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:FabricBase = 'https://api.fabric.microsoft.com/v1'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Config = Get-Content -LiteralPath (Join-Path $script:Root 'config.example.json') -Raw | ConvertFrom-Json
$localConfig = Join-Path $script:Root 'config.local.json'
if (Test-Path -LiteralPath $localConfig) {
    $script:Config = Get-Content -LiteralPath $localConfig -Raw | ConvertFrom-Json
}
if ($script:Config.workspaceId -ne '21733624-95b6-4740-b892-d29ff7889aa4' -or
    $script:Config.folderId -ne '975ffc5a-edee-4558-a62d-3a2bfe72110c') {
    throw 'This deployment is restricted to the approved OilandGas workspace/folder.'
}

function Resolve-DemoIngestionMode([Collections.IDictionary]$State,[string]$Requested='') {
    $mode=if($Requested){$Requested}elseif($State.Contains('eventstreamIngestionMode')){
        $State['eventstreamIngestionMode']
    }else{'ProcessedIngestion'}
    if($mode -notin 'ProcessedIngestion','DirectIngestion'){throw 'Unknown saved/requested Eventstream ingestion mode.'}
    return $mode
}

function Get-AccessToken([string]$Resource) {
    $token = & az account get-access-token --resource $Resource --query accessToken --output tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Azure CLI could not authenticate to $Resource."
    }
    return $token.Trim()
}

function Invoke-Fabric([string]$Method, [string]$Path, $Body = $null) {
    $uri = if ($Path.StartsWith('https://')) { $Path } else { "$script:FabricBase/$Path" }
    $parsedUri = [uri]$uri
    if ($parsedUri.Host -eq 'msitapi.fabric.microsoft.com') {
        $uri = 'https://api.fabric.microsoft.com' + $parsedUri.PathAndQuery
        $parsedUri = [uri]$uri
    }
    $regionalOperation = $parsedUri.Host -like '*.analysis.windows.net' -and $parsedUri.AbsolutePath -match '^/v1/operations/[a-f0-9-]+(/result)?$'
    if ($parsedUri.Host -ne 'api.fabric.microsoft.com' -and -not $regionalOperation) { throw "Unexpected Fabric API host in $uri" }
    $headers = @{ Authorization = 'Bearer ' + (Get-AccessToken 'https://api.fabric.microsoft.com'); Accept = 'application/json' }
    $args = @{ Method = $Method; Uri = $uri; Headers = $headers; ContentType = 'application/json' }
    if ($null -ne $Body) { $args.Body = $Body | ConvertTo-Json -Depth 100 -Compress }
    $response = Invoke-WebRequest @args
    if ($response.StatusCode -eq 202) {
        $location = [string]@($response.Headers['Location'])[0]
        if ([string]::IsNullOrWhiteSpace($location)) { throw 'Accepted operation has no Location.' }
        $deadline = [DateTime]::UtcNow.AddMinutes(10)
        do {
            if ([DateTime]::UtcNow -gt $deadline) { throw "Fabric operation timed out: $location" }
            Start-Sleep -Seconds 3
            $operation = Invoke-Fabric 'GET' $location
        } while ($operation.status -in 'NotStarted','Running')
        if ($operation.status -ne 'Succeeded') {
            throw "Fabric operation failed: $($operation | ConvertTo-Json -Depth 15 -Compress)"
        }
        if ($Method -eq 'POST' -and $Path -notmatch 'updateDefinition|/jobs/|/refresh|/stop|/start') {
            return Invoke-Fabric 'GET' ($location.TrimEnd('/') + '/result')
        }
        return $operation
    }
    if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
    return $response.Content | ConvertFrom-Json -Depth 100
}

function Get-FabricCollection([string]$Path) {
    $values = [Collections.Generic.List[object]]::new()
    do {
        $page = Invoke-Fabric 'GET' $Path
        foreach ($value in $page.value) { $values.Add($value) }
        $Path = if ($page.PSObject.Properties['continuationUri']) { $page.continuationUri } else { $null }
    } while ($Path)
    return $values.ToArray()
}

function Assert-Target {
    $folder = Invoke-Fabric 'GET' "workspaces/$($script:Config.workspaceId)/folders/$($script:Config.folderId)"
    if ($folder.displayName -ne 'OilandGas' -or $folder.parentFolderId -ne 'ae614789-c3eb-4010-84c8-3c1bf662dbfd') {
        throw 'Target folder ancestry does not match Dev/Matthieu/OilandGas.'
    }
    $parent = Invoke-Fabric 'GET' "workspaces/$($script:Config.workspaceId)/folders/$($folder.parentFolderId)"
    if ($parent.displayName -ne 'Matthieu' -or $parent.parentFolderId -ne '00676919-1d4d-43de-9f69-9319e8a34651') {
        throw 'Unexpected parent folder.'
    }
    $dev = Invoke-Fabric 'GET' "workspaces/$($script:Config.workspaceId)/folders/$($parent.parentFolderId)"
    if ($dev.displayName -ne 'Dev') { throw 'Unexpected Dev folder.' }
}

function New-Part([string]$Path, [string]$Content) {
    return @{ path = $Path; payloadType = 'InlineBase64'
        payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Content)) }
}

function Set-DemoItem([string]$Name, [string]$Type, [array]$Parts = @(), [string]$Format = '') {
    Assert-Target
    $items = @(Get-FabricCollection "workspaces/$($script:Config.workspaceId)/items?rootFolderId=$($script:Config.folderId)&recursive=false")
    $matchingItems = @($items | Where-Object { $_.displayName -eq $Name -and $_.type -eq $Type })
    if ($matchingItems.Count -gt 1) { throw "Ambiguous item name/type: $Name ($Type)" }
    $conflicts = @($items | Where-Object {
        $_.displayName -eq $Name -and $_.type -ne $Type -and
        -not ($Type -eq 'Lakehouse' -and $_.type -eq 'SQLEndpoint')
    })
    if ($conflicts.Count) { throw "Unexpected type collision for $Name" }
    $definition = @{ parts = $Parts }
    if ($Format) { $definition.format = $Format }
    if ($matchingItems.Count -eq 1) {
        $item = $matchingItems[0]
        if ($item.type -ne $Type -or $item.folderId -ne $script:Config.folderId) { throw "Unexpected type/folder for $Name" }
        if ($Parts.Count) {
            Invoke-Fabric 'POST' "workspaces/$($script:Config.workspaceId)/items/$($item.id)/updateDefinition" @{ definition = $definition } | Out-Null
        }
        return $item
    }
    $body = @{ displayName = $Name; type = $Type; folderId = $script:Config.folderId }
    if ($Parts.Count) { $body.definition = $definition }
    $result = Invoke-Fabric 'POST' "workspaces/$($script:Config.workspaceId)/items" $body
    Write-Host "Created $Type $Name ($($result.id))"
    return $result
}

function Invoke-Kql([string]$Query, [switch]$Management) {
    $state = Get-Content -LiteralPath (Join-Path $script:Root 'local-only\deployment.json') -Raw | ConvertFrom-Json
    if ($state.workspaceId -ne $script:Config.workspaceId -or $state.folderId -ne $script:Config.folderId) { throw 'Deployment state target mismatch.' }
    $hostName = ([uri]$state.queryServiceUri).Host
    if ($hostName -notlike '*.kusto.fabric.microsoft.com') { throw 'Unexpected Kusto endpoint.' }
    $path = if ($Management) { 'mgmt' } else { 'query' }
    $response = Invoke-RestMethod -Method Post -Uri "$($state.queryServiceUri.TrimEnd('/'))/v1/rest/$path" `
        -Headers @{ Authorization = 'Bearer ' + (Get-AccessToken 'https://api.kusto.windows.net'); Accept = 'application/json' } `
        -ContentType 'application/json' -Body (@{ db = $state.databaseName; csl = $Query } | ConvertTo-Json -Depth 20)
    if ($response.PSObject.Properties['error']) { throw ($response.error | ConvertTo-Json -Depth 10) }
    foreach ($table in $response.Tables) {
        if ($table.TableName -eq 'QueryStatus') {
            foreach ($row in $table.Rows) {
                if ($row[2] -is [int] -and $row[2] -ge 2) { throw "KQL query status: $($row -join ' ')" }
            }
        }
    }
    return $response
}

function Get-KqlIngestionExtentIds([object]$Response) {
    $tables=@($Response.Tables|Where-Object {'ExtentId' -in $_.Columns.ColumnName})
    if($tables.Count -ne 1 -or @($tables[0].Rows).Count -eq 0){
        throw 'Inline ingestion did not return an extent acknowledgement. Do not blindly retry.'
    }
    $index=[array]::IndexOf(@($tables[0].Columns.ColumnName),'ExtentId')
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach($row in $tables[0].Rows){
        $extent=[guid]::Empty
        if(-not [guid]::TryParse([string]$row[$index],[ref]$extent) -or $extent -eq [guid]::Empty -or
            -not $seen.Add($extent.ToString())){
            throw 'Inline ingestion returned an invalid, empty or duplicate extent acknowledgement. Do not blindly retry.'
        }
        $extent.ToString()
    }
}

function Invoke-KqlFile([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw
    $commands = [regex]::Matches($text, '(?m)^\.[a-z]')
    for ($i = 0; $i -lt $commands.Count; $i++) {
        $end = if ($i + 1 -lt $commands.Count) { $commands[$i + 1].Index } else { $text.Length }
        $command = $text.Substring($commands[$i].Index, $end - $commands[$i].Index).Trim()
        Write-Host (($command -split "`n")[0])
        Invoke-Kql $command -Management | Out-Null
    }
}
