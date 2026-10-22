function Test-AgentAnswer {
    param(
        [Parameter(Mandatory)][object]$Response,
        [Parameter(Mandatory)][ValidateSet('HighCount','OntologyPath','GraphPath','CurrentStale','SiteInventory','CompareHistorical','AmbiguousAsset')][string]$Case,
        [DateTimeOffset]$ObservedAtUtc=[DateTimeOffset]::UtcNow,
        [object[]]$ExpectedRows=@()
    )
    $csv=@($Response.content|Where-Object {
        $_.type -eq 'resource' -and $_.resource.mimeType -eq 'text/csv'
    })
    if($csv.Count -ne 1){return $false}
    $rows=@($csv[0].resource.text|ConvertFrom-Csv)
    if($Case -in 'SiteInventory','AmbiguousAsset'){
        if($rows.Count -ne 6){return $false}
        $assets=if($Case -eq 'SiteInventory'){@('CMP-A1','CMP-A2')}else{@('CMP-A1','CMP-B1')}
        $metrics=@{DP='DischargePressure';SP='SuctionPressure';VB='Vibration'}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($row in $rows){
            foreach($column in 'MeasurementId','AssetId','SiteId','Metric','EngineeringUnit','AsOfUtc','EventTime','IsStale'){
                if(-not $row.PSObject.Properties[$column]){return $false}
            }
            $id=[regex]::Match($row.MeasurementId,'^MSR-([AB][12])-(DP|SP|VB)$')
            if(-not $id.Success -or -not $seen.Add($row.MeasurementId)){return $false}
            $asset='CMP-'+$id.Groups[1].Value
            $site='SITE-'+$id.Groups[1].Value.Substring(0,1)
            $unit=if($id.Groups[2].Value -eq 'VB'){'mm/s'}else{'psi'}
            if($asset -cnotin $assets -or $row.AssetId -cne $asset -or $row.SiteId -cne $site -or
                $row.Metric -cne $metrics[$id.Groups[2].Value] -or $row.EngineeringUnit -cne $unit -or
                $row.IsStale -notin 'true','1'){return $false}
            $asOf=[DateTimeOffset]::MinValue
            if(-not [DateTimeOffset]::TryParse($row.AsOfUtc,[ref]$asOf) -or $asOf.Offset -ne [TimeSpan]::Zero -or
                $asOf -lt $ObservedAtUtc.AddMinutes(-5) -or $asOf -gt $ObservedAtUtc.AddSeconds(30)){return $false}
            if($row.EventTime){
                $eventTime=[DateTimeOffset]::MinValue
                if(-not [DateTimeOffset]::TryParse($row.EventTime,[ref]$eventTime) -or $eventTime -ge $asOf.AddSeconds(-60)){return $false}
            }
        }
        if($Case -eq 'AmbiguousAsset'){
            $text=(@($Response.content|Where-Object type -eq 'text'|Select-Object -ExpandProperty text) -join "`n")
            return $text -match '\bnot a diagnosis\b'
        }
        return $true
    }
    if($Case -eq 'CompareHistorical'){
        if($rows.Count -ne 6 -or $ExpectedRows.Count -ne 6){return $false}
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach($row in $rows){
            foreach($column in 'AssetId','Metric','EngineeringUnit','Average','Minimum','Maximum','Samples','LatestTime','ObservationWindowStart','ObservationWindowEnd'){
                if(-not $row.PSObject.Properties[$column]){return $false}
            }
            $key="$($row.AssetId)|$($row.Metric)|$($row.EngineeringUnit)"
            if(-not $seen.Add($key)){return $false}
            $expected=@($ExpectedRows|Where-Object {
                $_.AssetId -ceq $row.AssetId -and $_.Metric -ceq $row.Metric -and $_.EngineeringUnit -ceq $row.EngineeringUnit
            })
            if($expected.Count -ne 1 -or $row.Samples -cne [string]$expected[0].Samples -or
                $row.ObservationWindowStart -cne '2026-10-20T11:00:00Z' -or $row.ObservationWindowEnd -cne '2026-10-20T12:00:00Z'){return $false}
            foreach($column in 'Average','Minimum','Maximum'){
                $value=[double]::NaN
                if(-not [double]::TryParse($row.$column,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value) -or
                    -not [double]::IsFinite($value) -or [Math]::Abs($value-[double]$expected[0].$column) -gt 0.000000001){return $false}
            }
            $latest=[DateTimeOffset]::MinValue
            if(-not [DateTimeOffset]::TryParse($row.LatestTime,[ref]$latest) -or $latest.Offset -ne [TimeSpan]::Zero -or
                $latest -ne [DateTimeOffset]$expected[0].LatestTime){return $false}
        }
        return $true
    }
    if($Case -eq 'CurrentStale'){
        if($rows.Count -ne 12){return $false}
        $missing=0
        foreach($row in $rows){
            foreach($column in 'FreshCount','StaleCount','MissingCount','AsOfUtc','MeasurementId','EngineeringUnit','EventTime','FreshnessStatus'){
                if(-not $row.PSObject.Properties[$column]){return $false}
            }
            if($row.MeasurementId -cnotmatch '^MSR-([AB][12])-(DP|SP|VB)$'){return $false}
            $unit=if($Matches[2] -eq 'VB'){'mm/s'}else{'psi'}
            if($row.FreshCount -cne '0' -or $row.StaleCount -cne '12' -or $row.EngineeringUnit -cne $unit){return $false}
            $asOf=[DateTimeOffset]::MinValue
            if(-not [DateTimeOffset]::TryParse($row.AsOfUtc,[ref]$asOf) -or $asOf.Offset -ne [TimeSpan]::Zero -or
                $asOf -lt $ObservedAtUtc.AddMinutes(-5) -or $asOf -gt $ObservedAtUtc.AddSeconds(30)){return $false}
            if([string]::IsNullOrEmpty($row.EventTime)){
                $missing++
                if($row.FreshnessStatus -notin 'Missing','No data','NoData'){return $false}
            }else{
                $eventTime=[DateTimeOffset]::MinValue
                if(-not [DateTimeOffset]::TryParse($row.EventTime,[ref]$eventTime) -or
                    $eventTime -ge $asOf.AddSeconds(-60) -or $row.FreshnessStatus -cne 'Stale'){return $false}
            }
        }
        return @($rows|Select-Object -ExpandProperty MeasurementId -Unique).Count -eq 12 -and
            @($rows|Where-Object {$_.MissingCount -cne [string]$missing}).Count -eq 0
    }
    if($rows.Count -ne 1){return $false}
    $expected=if($Case -eq 'HighCount'){
        @{
            EngineeringUnit='psi';UniqueHighPressureReadings='10'
            ObservationWindowStart='2026-10-20T11:00:00Z';ObservationWindowEnd='2026-10-20T12:00:00Z'
        }
    }else{
        @{
            SiteId='SITE-A';BatteryId='BAT-A';SystemId='SYS-A';CompressorId='CMP-A1'
            ComponentId='THR-A1';MeasurementId='MSR-A1-DP';Source='SyntheticSCADA';UnitNum='1'
            Name='Fictional_Aspen/Tank_Battery/Gas_Lift/Compressors/Compressor_1/Performance/Throw_3/DisplayedDiscPress'
            EngineeringUnit='psi'
        }
    }
    foreach($entry in $expected.GetEnumerator()){
        if(-not $rows[0].PSObject.Properties[$entry.Key] -or $rows[0].($entry.Key) -cne $entry.Value){return $false}
    }
    return $true
}
