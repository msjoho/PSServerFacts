function Format-RunSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [Parameter(Mandatory)][string]$StartedUtc,
        [Parameter(Mandatory)][string]$FinishedUtc
    )

    $sb = [System.Text.StringBuilder]::new()
    $w  = { param($s) [void]$sb.AppendLine($s) }

    $total      = @($Results).Count
    $succeeded  = @($Results | Where-Object Status -eq 'Success').Count
    $failed     = @($Results | Where-Object Status -eq 'Failed').Count
    $partial    = @($Results | Where-Object Status -eq 'PartialSuccess').Count

    & $w "# Server Assessment Summary"
    & $w ""
    & $w "**Run:** $StartedUtc -> $FinishedUtc $([char]0x00B7) **Servers:** $total $([char]0x00B7) **Succeeded:** $succeeded $([char]0x00B7) **Partial:** $partial $([char]0x00B7) **Failed:** $failed"
    & $w ""
    & $w "## Per-server status"
    & $w "| Server | Status | Duration | Custom services | Custom shares | Custom tasks | IIS sites | Errors |"
    & $w "|---|---|---:|---:|---:|---:|---:|---:|"
    foreach ($r in $Results) {
        $iisSites = if ($r.PSObject.Properties['Iis'] -and $r.Iis) { @($r.Iis.Sites).Count } else { '-' }
        $svc = if ($r.PSObject.Properties['Services']) { @($r.Services).Count } else { 0 }
        $sh  = if ($r.PSObject.Properties['Shares'])   { @($r.Shares).Count } else { 0 }
        $st  = if ($r.PSObject.Properties['ScheduledTasks']) { @($r.ScheduledTasks).Count } else { 0 }
        $errCount = if ($r.PSObject.Properties['Errors']) { @($r.Errors).Count } else { 0 }
        & $w "| $($r.Computer) | $($r.Status) | $($r.DurationSeconds)s | $svc | $sh | $st | $iisSites | $errCount |"
    }

    & $w ''
    & $w '## Advisories by server'
    & $w ''
    & $w '| Server | Critical | Warnings | Notes |'
    & $w '|---|---:|---:|---:|'
    foreach ($r in @($Results | Sort-Object Computer)) {
        $adv = @($r.PSObject.Properties['AdvisoriesComputed'].Value | Where-Object { $null -ne $_ })
        $c   = @($adv | Where-Object Severity -eq 'Critical').Count
        $wn  = @($adv | Where-Object Severity -eq 'Warning').Count
        $n   = @($adv | Where-Object Severity -eq 'Note').Count
        & $w "| $($r.Computer) | $c | $wn | $n |"
    }

    $failedList = @($Results | Where-Object Status -eq 'Failed')
    if ($failedList.Count -gt 0) {
        & $w ""
        & $w "## Failed servers"
        foreach ($f in $failedList) {
            $msg = ($f.Errors | ForEach-Object { $_.Message }) -join '; '
            & $w "- **$($f.Computer)** - $msg"
        }
    }

    # Aggregate domain service accounts
    $allAccounts = @{}
    foreach ($r in $Results) {
        if (-not $r.PSObject.Properties['ServiceAccounts']) { continue }
        foreach ($a in @($r.ServiceAccounts)) {
            if (-not $allAccounts.ContainsKey($a.Account)) { $allAccounts[$a.Account] = [System.Collections.Generic.List[object]]::new() }
            foreach ($u in @($a.UsedBy)) {
                $name = if ($u.PSObject.Properties['Name']) { $u.Name } else { $u.Path }
                $allAccounts[$a.Account].Add([pscustomobject]@{ Server = $r.Computer; Kind = $u.Kind; Name = $name })
            }
        }
    }
    if ($allAccounts.Count -gt 0) {
        & $w ""
        & $w "## Aggregate domain service accounts"
        & $w "| Account | Servers / uses |"
        & $w "|---|---|"
        foreach ($k in ($allAccounts.Keys | Sort-Object)) {
            $uses = ($allAccounts[$k] | ForEach-Object { "$($_.Server) ($($_.Kind): $($_.Name))" }) -join '; '
            & $w "| ``$k`` | $uses |"
        }
    }

    # Certs expiring within 90 days
    $expiring = foreach ($r in $Results) {
        if (-not $r.PSObject.Properties['Certificates']) { continue }
        foreach ($c in @($r.Certificates) | Where-Object { $_.DaysUntilExpiry -le 90 -and -not $_.Expired }) {
            [pscustomobject]@{
                Server = $r.Computer; Store = $c.Store; Subject = $c.Subject
                Thumbprint = $c.Thumbprint; NotAfterUtc = $c.NotAfterUtc
                DaysUntilExpiry = $c.DaysUntilExpiry
            }
        }
    }
    if ($expiring) {
        & $w ""
        & $w "## Certificates expiring within 90 days"
        & $w "| Server | Store | Subject | Thumbprint | Not after | Expires in |"
        & $w "|---|---|---|---|---|---|"
        foreach ($e in $expiring | Sort-Object DaysUntilExpiry) {
            & $w "| $($e.Server) | ``$($e.Store)`` | $($e.Subject) | ``$($e.Thumbprint)`` | $($e.NotAfterUtc) | $([char]0x26A0) $($e.DaysUntilExpiry) d |"
        }
    }

    # SQL Server cross-server block
    $sqlInstances = @(
        foreach ($r in $Results) {
            if ($r.PSObject.Properties['CollectedSections'] -and 'SqlServer' -in $r.CollectedSections -and $r.SqlServer) {
                foreach ($inst in @($r.SqlServer)) {
                    $inst | Add-Member -NotePropertyName _Computer -NotePropertyValue $r.Computer -Force -PassThru
                }
            }
        }
    )

    if ($sqlInstances.Count -gt 0) {
        & $w ""
        & $w "## SQL Server (cross-server)"
        & $w ""

        $serverCount = ($sqlInstances | Group-Object _Computer).Count
        $userDbCount = (@($sqlInstances | ForEach-Object { @($_.Databases | Where-Object { -not $_.IsSystem }) }).Count)
        & $w "### Instances overview"
        $dot = [char]0x00B7
        & $w "**Total instances:** $($sqlInstances.Count) across $serverCount servers  $dot  **Total user databases:** $userDbCount"
        & $w ""

        # Editions
        & $w "### Editions"
        & $w "| Edition | Instances |"
        & $w "|---|---|"
        foreach ($g in ($sqlInstances | Group-Object Edition | Sort-Object Count -Descending)) {
            & $w "| $($g.Name) | $($g.Count) |"
        }
        & $w ""

        # Versions
        & $w "### Versions"
        & $w "| Version | Instances |"
        & $w "|---|---|"
        foreach ($g in ($sqlInstances | Group-Object Version | Sort-Object Count -Descending)) {
            & $w "| $($g.Name) | $($g.Count) |"
        }
        & $w ""

        # Always On topology
        $allAgs = @($sqlInstances | ForEach-Object { @($_.AvailabilityGroups) | Where-Object { $_ } })
        if ($allAgs.Count -gt 0) {
            $byAg = $allAgs | Group-Object Name
            & $w "### Always On topology"
            & $w "| AG | Cluster | Replicas (role $dot sync) |"
            & $w "|---|---|---|"
            foreach ($g in $byAg) {
                $ag = $g.Group | Select-Object -First 1
                $reps = ($ag.Replicas | ForEach-Object {
                    $sync = if ($_.AvailabilityMode -match 'Synchronous') { 'Sync' } else { 'Async' }
                    "$($_.Name) ($($_.Role) $dot $sync)"
                }) -join ', '
                & $w "| $($ag.Name) | $($ag.ClusterType) | $reps |"
            }
            & $w ""
        }

        # Linked-server dependencies
        $allLinked = foreach ($inst in $sqlInstances) {
            foreach ($ls in @($inst.LinkedServers)) {
                [pscustomobject]@{ Source = $inst.ServerName; Target = $ls.DataSource; Product = $ls.Product }
            }
        }
        if (@($allLinked).Count -gt 0) {
            & $w "### Linked-server dependencies"
            & $w "| Source | -> Linked to | Product |"
            & $w "|---|---|---|"
            foreach ($l in $allLinked) {
                & $w "| $($l.Source) | $($l.Target) | $($l.Product) |"
            }
            & $w ""
        }

        # Backup hygiene warnings
        $now = Get-Date
        $stale = foreach ($inst in $sqlInstances) {
            foreach ($b in @($inst.Backups)) {
                if (-not $b.LastFull) {
                    [pscustomobject]@{ ServerInst=$inst.ServerName; Database=$b.DatabaseName; LastFull='(never)' }
                } elseif ((($now - [datetime]$b.LastFull.BackupAtUtc).TotalDays) -gt 7) {
                    [pscustomobject]@{ ServerInst=$inst.ServerName; Database=$b.DatabaseName; LastFull=([datetime]$b.LastFull.BackupAtUtc).ToString('yyyy-MM-dd') }
                }
            }
        }
        if (@($stale).Count -gt 0) {
            & $w "### Backup hygiene (warnings)"
            & $w "**DBs missing recent full backup (>7 days or never):**"
            & $w "| Server\Instance | Database | Last Full |"
            & $w "|---|---|---|"
            foreach ($s in $stale) {
                & $w "| $($s.ServerInst) | $($s.Database) | $($s.LastFull) |"
            }
            & $w ""
        }

        # Connection failures
        $failedInst = $sqlInstances | Where-Object { $_.ConnectionMethod -eq 'Failed' }
        if (@($failedInst).Count -gt 0) {
            & $w "### Connection failures"
            & $w "| Server\Instance | Reason |"
            & $w "|---|---|"
            foreach ($f in $failedInst) {
                $reason = ($Results | Where-Object Computer -eq $f._Computer | ForEach-Object { @($_.Errors) } |
                    Where-Object Section -eq 'SqlServer' | Select-Object -First 1).Message
                & $w "| $($f.ServerName) | $reason |"
            }
            & $w ""
        }

        # Footnote for RegistryOnly instances
        $regOnly = ($sqlInstances | Where-Object ConnectionMethod -eq 'RegistryOnly').Count
        if ($regOnly -gt 0) {
            & $w "_$regOnly instances had no live-query data - see per-server reports_"
        }
    }

    return $sb.ToString()
}
