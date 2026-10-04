function Format-SqlServerInstanceBlock {
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Instance)

    $sb  = [System.Text.StringBuilder]::new()
    $w   = { param($s) [void]$sb.AppendLine($s) }
    $dot = [char]0x00B7
    $i   = $Instance

    & $w "### Instance: $($i.InstanceName)  $dot  $($i.Version) $($i.Edition) ($($i.PatchLevel))"
    & $w "**Collation:** $($i.Collation)  $dot  **Auth Mode:** $($i.AuthenticationMode)  $dot  **Clustered:** $(if ($i.IsClustered) { 'Yes' } else { 'No' })"
    if ($i.ServiceAccounts.Engine)  { & $w "**Engine Service:** $($i.ServiceAccounts.Engine.Account) ($($i.ServiceAccounts.Engine.StartMode), $($i.ServiceAccounts.Engine.State))" }
    if ($i.ServiceAccounts.Agent)   { & $w "**Agent Service:** $($i.ServiceAccounts.Agent.Account) ($($i.ServiceAccounts.Agent.StartMode), $($i.ServiceAccounts.Agent.State))" }
    & $w "**Features:** $(@($i.InstalledFeatures) -join ', ')"
    & $w "**Connection:** $($i.ConnectionMethod)"
    if ($i.ConnectionError) { & $w "$([char]0x26A0) **Connection error:** $($i.ConnectionError)" }
    if ($i.LiveQueryError)  { & $w "$([char]0x26A0) **Live-query error:** $($i.LiveQueryError)" }
    & $w ""

    if ($i.Configuration) {
        & $w '#### Configuration'
        & $w '| Setting | Value |'
        & $w '|---|---|'
        foreach ($pair in @(
            @('Max Memory (MB)', $i.Configuration.MaxMemoryMB),
            @('Min Memory (MB)', $i.Configuration.MinMemoryMB),
            @('MAXDOP',          $i.Configuration.MaxDop),
            @('Cost Threshold for Parallelism', $i.Configuration.CostThresholdForParallelism),
            @('Default Data Path', $i.Configuration.DefaultDataPath),
            @('Default Log Path',  $i.Configuration.DefaultLogPath),
            @('Backup Directory',  $i.Configuration.BackupDirectory)
        )) { & $w "| $($pair[0]) | $($pair[1]) |" }
        & $w ""
    }

    if (@($i.InstalledUpdates).Count -gt 0) {
        & $w "#### Installed Updates (n=$(@($i.InstalledUpdates).Count))"
        & $w '| KB | Version | Installed (UTC) |'
        & $w '|---|---|---|'
        foreach ($u in $i.InstalledUpdates) {
            $when = if ($u.InstalledUtc) { ([datetime]$u.InstalledUtc).ToString('yyyy-MM-dd') } else { '' }
            & $w "| $($u.KB) | $($u.Version) | $when |"
        }
        & $w ""
    }

    if (@($i.Logins).Count -gt 0) {
        & $w "#### Server-Level Logins (n=$(@($i.Logins).Count))"
        & $w '| Login | Type | Disabled | Server Roles | Database Access |'
        & $w '|---|---|---|---|---|'
        foreach ($l in $i.Logins) {
            $disabled = if ($l.Disabled) { [char]0x2705 } else { [char]0x274C }
            $sr = if (@($l.ServerRoles).Count -gt 0) { @($l.ServerRoles) -join ', ' } else { '*(none)*' }
            $da = if (@($l.DatabaseAccess).Count -gt 0) {
                ($l.DatabaseAccess | ForEach-Object { "$($_.Database):$(@($_.Roles) -join ',')" }) -join '; '
            } else { '*(none)*' }
            & $w "| $($l.Name) | $($l.Type) | $disabled | $sr | $da |"
        }
        & $w ""
    }

    if (@($i.OrphanDatabaseUsers).Count -gt 0) {
        & $w "#### Orphan Database Users (n=$(@($i.OrphanDatabaseUsers).Count))"
        & $w '| Database | DB User | Roles |'
        & $w '|---|---|---|'
        foreach ($o in $i.OrphanDatabaseUsers) {
            & $w "| $($o.Database) | $($o.DatabaseUser) | $(@($o.Roles) -join ', ') |"
        }
        & $w ""
    }

    if (@($i.LinkedServers).Count -gt 0) {
        & $w "#### Linked Servers (n=$(@($i.LinkedServers).Count))"
        & $w '| Name | Product | Data Source | Security Mode |'
        & $w '|---|---|---|---|'
        foreach ($ls in $i.LinkedServers) {
            & $w "| $($ls.Name) | $($ls.Product) | $($ls.DataSource) | $($ls.SecurityMode) |"
        }
        & $w ""
    }

    if (@($i.Databases).Count -gt 0) {
        $sysCount  = @($i.Databases | Where-Object IsSystem).Count
        $userCount = @($i.Databases | Where-Object { -not $_.IsSystem }).Count
        & $w "#### Databases ($userCount user, $sysCount system)"
        & $w '| Name | System | Collation | Recovery | Compat | Owner | Status | Size MB |'
        & $w '|---|---|---|---|---|---|---|---|'
        foreach ($db in $i.Databases) {
            $sys = if ($db.IsSystem) { [char]0x2705 } else { [char]0x274C }
            & $w "| $($db.Name) | $sys | $($db.Collation) | $($db.RecoveryModel) | $($db.CompatibilityLevel) | $($db.Owner) | $($db.Status) | $($db.SizeMB) |"
        }
        & $w ""
    }

    if (@($i.DiskLayout).Count -gt 0) {
        & $w '#### Disk Layout'
        & $w '| Drive | Used For | Total GB | Free GB |'
        & $w '|---|---|---|---|'
        foreach ($d in $i.DiskLayout) {
            & $w "| $($d.Drive) | $(@($d.Roles) -join ', ') | $($d.TotalGB) | $($d.FreeGB) |"
        }
        & $w ""
    }

    if (@($i.AvailabilityGroups).Count -gt 0) {
        & $w "#### Always On Availability Groups (n=$(@($i.AvailabilityGroups).Count))"
        & $w '| AG | Cluster | Role | Replica | Sync Mode | Failover | Listener |'
        & $w '|---|---|---|---|---|---|---|'
        foreach ($ag in $i.AvailabilityGroups) {
            $listener = if ($ag.Listener) { "$($ag.Listener.Name):$($ag.Listener.Port)" } else { '' }
            foreach ($rep in @($ag.Replicas)) {
                $sync = if ($rep.AvailabilityMode -match 'Synchronous') { 'Sync' } else { 'Async' }
                & $w "| $($ag.Name) | $($ag.ClusterType) | $($rep.Role) | $($rep.Name) | $sync | $($rep.FailoverMode) | $listener |"
            }
            if (@($ag.Databases).Count -gt 0) {
                & $w ""
                & $w "**Databases in $($ag.Name):** $(@($ag.Databases) -join ', ')"
            }
        }
        & $w ""
    }

    if (@($i.AgentJobs).Count -gt 0) {
        & $w "#### SQL Agent Jobs (n=$(@($i.AgentJobs).Count))"
        & $w '| Job | Enabled | Owner | Category | Schedules | Last Run (UTC) | Outcome | Next Run (UTC) |'
        & $w '|---|---|---|---|---|---|---|---|'
        foreach ($j in $i.AgentJobs) {
            $en  = if ($j.Enabled) { [char]0x2705 } else { [char]0x274C }
            $sch = if (@($j.Schedules).Count -gt 0) { (@($j.Schedules) | ForEach-Object Summary) -join '; ' } else { '*(none)*' }
            $lr  = if ($j.LastRunUtc) { ([datetime]$j.LastRunUtc).ToString('yyyy-MM-dd HH:mm') } else { '' }
            $nr  = if ($j.NextRunUtc) { ([datetime]$j.NextRunUtc).ToString('yyyy-MM-dd HH:mm') } else { '' }
            & $w "| $($j.Name) | $en | $($j.Owner) | $($j.Category) | $sch | $lr | $($j.LastRunOutcome) | $nr |"
        }
        & $w ""
    }

    if (@($i.Backups).Count -gt 0) {
        & $w '#### Backups (per database)'
        & $w '| Database | Last Full | Last Diff | Last Log |'
        & $w '|---|---|---|---|'
        $now  = Get-Date
        $cell = {
            param($x)
            if (-not $x) { return "$([char]0x26A0) never" }
            $when = ([datetime]$x.BackupAtUtc).ToString('yyyy-MM-dd HH:mm')
            $age  = ($now - [datetime]$x.BackupAtUtc).TotalDays
            $prefix = if ($age -gt 7) { "$([char]0x26A0) " } else { '' }
            "$prefix$when ($($x.SizeMB) MB)"
        }
        foreach ($b in $i.Backups) {
            & $w "| $($b.DatabaseName) | $(& $cell $b.LastFull) | $(& $cell $b.LastDiff) | $(& $cell $b.LastLog) |"
        }
        & $w ""
    }

    if (@($i.BackupDirectoryAcls).Count -gt 0) {
        & $w '#### Backup Directory'
        foreach ($acl in $i.BackupDirectoryAcls) {
            if ($acl.Error) {
                & $w "$([char]0x26A0) Could not read ACL on $($acl.Path): $($acl.Error)"
                & $w ""
                continue
            }
            $readSuffix = if ($acl.ReadFrom) { "  $dot  **Read from:** $($acl.ReadFrom)" } else { '' }
            & $w "**Path:** $($acl.Path)  $dot  **Type:** $($acl.PathType)  $dot  **Owner:** $($acl.Owner)$readSuffix"
            & $w ""
            & $w "**Non-inherited NTFS ACEs** (n=$(@($acl.Entries).Count)):"
            & $w '| Identity | Rights | Access | Applies To | Type |'
            & $w '|---|---|---|---|---|'
            foreach ($e in $acl.Entries) {
                $type = if ($e.Principal -and $e.Principal.Type) { $e.Principal.Type } else { 'Unresolved' }
                & $w "| $($e.Account) | $($e.Rights) | $($e.AccessControlType) | $($e.AppliesTo) | $type |"
            }
            & $w ""

            # Group expansions appear only when -ExpandGroupMembers was set.
            $groupExpansions = @($acl.Entries | Where-Object {
                $_.Principal -and $_.Principal.Type -eq 'Group' -and ($_.PSObject.Properties['Members'])
            })
            if ($groupExpansions.Count -gt 0) {
                & $w '**Group expansions (recursive):**'
                & $w ''
                foreach ($e in $groupExpansions) {
                    if ($e.MembersSkipped) {
                        & $w "- **$($e.Account)** *(default group — recursion skipped)*"
                        continue
                    }
                    $members = @($e.Members)
                    & $w "- **$($e.Account)** ($($members.Count) members):"
                    foreach ($m in ($members | Sort-Object { $_.Account })) {
                        $name = if ($m.Account) { $m.Account } elseif ($m.DistinguishedName) { $m.DistinguishedName } else { $m.Sid }
                        $via  = if (@($m.Path).Count -gt 1) { "  *(via " + ((@($m.Path) | Select-Object -Skip 1) -join ' → ') + ')*' } else { '' }
                        & $w "  - $name [$($m.Type)]$via"
                    }
                }
                & $w ''
            }
        }
    }

    $sb.ToString()
}

function ConvertTo-ServerFactsMarkdown {
    <#
    .SYNOPSIS
        Render a server facts result object as a human-readable Markdown report.

    .DESCRIPTION
        ConvertTo-ServerFactsMarkdown takes one result object produced by Export-ServerFacts
        (or equivalently re-hydrated from a per-server JSON file) and returns the Markdown
        report as a single string. One ## heading is emitted per collected section, with
        filtered-count summaries on Services / Shares / ScheduledTasks / Firewall headings
        and Success / PartialSuccess / Failed status indicators.

        If advisories are present on the result (.AdvisoriesComputed), they are surfaced
        twice: once as a summary block immediately after the banner, and inline as
        blockquotes under the section they apply to.

        Export-ServerFacts calls this function automatically for every scanned server
        and writes the result to <server>.md in the run folder. Call it directly only
        when you want to re-render a stored JSON, transform the output further, or pipe
        it somewhere other than a file.

    .PARAMETER Result
        A server facts result object: either the live in-memory object returned by the
        per-server worker, or an object re-hydrated from <server>.json via
        Get-Content | ConvertFrom-Json. The function reads .Computer, .ScannedAtUtc,
        .ScannedBy, .DurationSeconds, .Status, and one property per collected section.

    .EXAMPLE
        $result = Get-Content .\output\2026-05-19_103045_001\srv01.json | ConvertFrom-Json
        ConvertTo-ServerFactsMarkdown -Result $result | Set-Content -Path .\srv01-rerender.md

        Re-render the Markdown from a previously-saved JSON. Useful when you've edited
        the formatter and want to refresh historical reports without re-scanning.

    .EXAMPLE
        Get-ChildItem .\output\latest\*.json |
            ForEach-Object {
                $r = Get-Content $_.FullName | ConvertFrom-Json
                ConvertTo-ServerFactsMarkdown -Result $r |
                    Set-Content -Path ($_.FullName -replace '\.json$','.md')
            }

        Re-render every per-server JSON in a run folder back into Markdown.

    .OUTPUTS
        System.String. The full Markdown report.

    .LINK
        Export-ServerFacts

    .LINK
        https://github.com/martin-joho/PSServerFacts
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Result)

    $sb = [System.Text.StringBuilder]::new()
    $w  = { param($s) [void]$sb.AppendLine($s) }
    $statusEmoji = switch ($Result.Status) {
        'Success'        { [char]0x2705 }
        'PartialSuccess' { [char]0x26A0 }     # warning sign
        'Failed'         { [char]0x274C }
        default          { '·' }
    }

    & $w "# Server Assessment: $($Result.Computer)"
    & $w ""
    & $w "**Scanned:** $($Result.ScannedAtUtc) by ``$($Result.ScannedBy)`` $([char]0x00B7) **Duration:** $($Result.DurationSeconds)s $([char]0x00B7) **Status:** $statusEmoji $($Result.Status)"

    if ($Result.Status -eq 'Failed') {
        & $w ""
        & $w "## Errors"
        foreach ($e in $Result.Errors) { & $w "- **$($e.Section):** $($e.Message)" }
        return $sb.ToString()
    }

    # Advisory plumbing — build a section-keyed lookup for inline blockquotes.
    $allAdv = @($Result.PSObject.Properties['AdvisoriesComputed'].Value | Where-Object { $null -ne $_ })
    $advBySection = @{}
    foreach ($a in $allAdv) {
        if (-not $advBySection.ContainsKey($a.Section)) {
            $advBySection[$a.Section] = New-Object System.Collections.Generic.List[object]
        }
        [void]$advBySection[$a.Section].Add($a)
    }
    $renderInlineFor = {
        param([string]$Section)
        if (-not $advBySection.ContainsKey($Section)) { return }
        foreach ($a in $advBySection[$Section]) {
            & $w ''
            & $w (Format-AdvisoryInlineLine -Advisory $a)
        }
    }

    # Emit the advisory summary block immediately after the banner.
    $summaryBlock = Format-AdvisorySummaryBlock -Advisories $allAdv
    if ($summaryBlock) {
        & $w ''
        & $w $summaryBlock
    }

    # Determine which sections were collected. Backward compat: if the field is
    # missing entirely (older fixture / legacy data), fall back to "all collected".
    $collected = if ($Result.PSObject.Properties['CollectedSections']) {
        @($Result.CollectedSections)
    } else {
        @('System','Hardware','Disks','Network','InstalledApplications',
          'ChocolateyPackages','WindowsFeatures','Permissions','Services','Shares',
          'ScheduledTasks','LocalUsers','FirewallRules','Iis','Certificates')
    }
    $isCollected = { param([string]$Name) $Name -in $collected }

    # System
    if (& $isCollected 'System') {
        & $w ""
        & $w "## System"
        & $w "| Property | Value |"
        & $w "|---|---|"
        & $w "| OS | $($Result.System.OsCaption) ($($Result.System.OsVersion) / $($Result.System.OsBuild)) |"
        & $w "| Installed | $($Result.System.InstallDateUtc) |"
        & $w "| Last boot | $($Result.System.LastBootUtc) |"
        if ($Result.System.LastHotfix) {
            & $w "| Last hotfix | $($Result.System.LastHotfix.HotFixId) — $($Result.System.LastHotfix.InstalledOnUtc) |"
        } else { & $w "| Last hotfix | *(none reported)* |" }
        & $w "| Domain | $($Result.System.Domain) |"
        & $w "| Time zone | $($Result.System.TimeZone) |"
        if ($Result.System.WinRmHttpsCertThumbprint) {
            & $w "| WinRM HTTPS cert | ``$($Result.System.WinRmHttpsCertThumbprint)`` |"
        }
        & $renderInlineFor 'System'
    }

    # Hardware
    if (& $isCollected 'Hardware') {
        & $w ""
        & $w "## Hardware"
        & $w "$($Result.Hardware.CpuSockets) × $($Result.Hardware.CpuModel) $([char]0x00B7) $($Result.Hardware.CpuLogicalCores) logical cores $([char]0x00B7) $($Result.Hardware.MemoryTotalGB) GB RAM"
        & $renderInlineFor 'Hardware'
    }

    # Disks
    if (& $isCollected 'Disks') {
        & $w ""
        & $w "## Disks"
        if (@($Result.Disks).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Drive | Label | FS | Total | Free | Used |"
            & $w "|---|---|---|---:|---:|---:|"
            foreach ($d in $Result.Disks) { & $w "| $($d.Drive) | $($d.Label) | $($d.FileSystem) | $($d.TotalGB) GB | $($d.FreeGB) GB | $($d.UsedPct)% |" }
        }
        & $renderInlineFor 'Disks'
    }

    # Network
    if (& $isCollected 'Network') {
        & $w ""
        & $w "## Network"
        if (@($Result.Network.Adapters).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Adapter | Status | IPv4 | Gateway | DNS |"
            & $w "|---|---|---|---|---|"
            foreach ($a in $Result.Network.Adapters) {
                $ipv4 = ($a.IPv4 | ForEach-Object { "$($_.Address)/$($_.PrefixLength)" }) -join ', '
                $dns  = $a.DnsServers -join ', '
                & $w "| $($a.Name) | $($a.Status) | $ipv4 | $($a.DefaultGateway) | $dns |"
            }
        }
        & $renderInlineFor 'Network'
    }

    # Permissions — two views per local group:
    #   1. "Direct members" — exactly what's on the local group (groups stay
    #      groups, users stay users). Mirrors `net localgroup <g>`.
    #   2. "Effective members" — recursive flat user list when
    #      -ExpandGroupMembers was set on the run; users reached via multiple
    #      groups have all paths joined by " ; ".
    if (& $isCollected 'Permissions') {
        & $w ""
        & $w "## Permissions"
        foreach ($g in 'Administrators','RemoteDesktopUsers','RemoteManagementUsers') {
            & $w ""
            & $w "### $g"
            $list = @($Result.Permissions.$g)
            if ($list.Count -eq 0) { & $w "*(none)*"; continue }

            & $w "#### Direct members"
            & $w "| Account | Type | Domain | DistinguishedName | Note |"
            & $w "|---|---|---|---|---|"
            foreach ($p in $list) {
                $note = if ($p.ResolveError) { $p.ResolveError } else { '' }
                & $w "| ``$($p.Account)`` | $($p.Type) | $($p.Domain) | $($p.DistinguishedName) | $note |"
            }

            $hasExpansion = [bool](@($list | Where-Object { $_.Type -eq 'Group' -and $_.PSObject.Properties['Members'] }).Count)
            if (-not $hasExpansion) { continue }

            & $w ""
            & $w "#### Effective members *(recursive)*"
            $effective = [ordered]@{}
            $upsert = {
                param($key, $row, $viaPath)
                if ([string]::IsNullOrWhiteSpace([string]$key)) { return }
                if ($effective.Contains($key)) {
                    if ($effective[$key].Paths -notcontains $viaPath) {
                        $effective[$key].Paths = @($effective[$key].Paths) + $viaPath
                    }
                } else {
                    $row | Add-Member -NotePropertyName Paths -NotePropertyValue @($viaPath) -Force
                    $effective[$key] = $row
                }
            }

            foreach ($p in $list) {
                $keyP = if ($p.Sid) { $p.Sid } else { $p.Account }
                if ($p.Type -eq 'Group' -and $p.PSObject.Properties['Members']) {
                    if ($p.MembersSkipped) {
                        # Default-group recursion suppressed — keep the group itself in the table.
                        $row = [pscustomobject]@{
                            Account = $p.Account; Type = 'Group (skipped)'
                            Name = $p.SamAccountName; Domain = $p.Domain
                            DistinguishedName = $p.DistinguishedName
                            Note = 'default group — recursion skipped'
                        }
                        & $upsert $keyP $row '(direct)'
                        continue
                    }
                    $members = @($p.Members)
                    if ($members.Count -eq 0) {
                        # Group expanded but had no resolvable members — keep the group row visible.
                        $row = [pscustomobject]@{
                            Account = $p.Account; Type = 'Group (empty)'
                            Name = $p.SamAccountName; Domain = $p.Domain
                            DistinguishedName = $p.DistinguishedName; Note = ''
                        }
                        & $upsert $keyP $row '(direct)'
                        continue
                    }
                    foreach ($m in $members) {
                        # Path on each member is the chain from the top-level group inward.
                        # Render only the chain ABOVE the leaf (i.e. the groups) joined with " → ".
                        $viaPath = @($m.Path) -join ' → '
                        if (-not $viaPath) { $viaPath = $p.Account }
                        $keyM = if ($m.Sid) { $m.Sid } else { $m.Account }
                        $row = [pscustomobject]@{
                            Account = $m.Account; Type = $m.Type
                            Name = $m.Name; Domain = $m.Domain
                            DistinguishedName = $m.DistinguishedName; Note = ''
                        }
                        & $upsert $keyM $row $viaPath
                    }
                    continue
                }
                # Top-level entry that is itself a leaf (LocalAccount / User / WellKnown / Unresolved /
                # Group without Members because -ExpandGroupMembers wasn't set).
                $note = if ($p.ResolveError) { $p.ResolveError } else { '' }
                $row = [pscustomobject]@{
                    Account = $p.Account; Type = $p.Type
                    Name = $p.SamAccountName; Domain = $p.Domain
                    DistinguishedName = $p.DistinguishedName; Note = $note
                }
                & $upsert $keyP $row '(direct)'
            }

            & $w "| Account | Domain | Type | Name | DistinguishedName | Inherited via | Note |"
            & $w "|---|---|---|---|---|---|---|"
            foreach ($e in ($effective.Values | Sort-Object Account)) {
                $via = @($e.Paths) -join ' ; '
                & $w "| ``$($e.Account)`` | $($e.Domain) | $($e.Type) | $($e.Name) | $($e.DistinguishedName) | $via | $($e.Note) |"
            }
        }
        & $renderInlineFor 'Permissions'
    }

    # Services
    if (& $isCollected 'Services') {
        & $w ""
        & $w "## Services *(custom only)*"
        if (@($Result.Services).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Name | DisplayName | State | StartMode | RunAs | Path |"
            & $w "|---|---|---|---|---|---|"
            foreach ($s in $Result.Services) { & $w "| $($s.Name) | $($s.DisplayName) | $($s.State) | $($s.StartMode) | ``$($s.StartName)`` | ``$($s.PathName)`` |" }
        }
        & $renderInlineFor 'Services'
    }

    # Shares
    if (& $isCollected 'Shares') {
        & $w ""
        & $w "## Shares *(custom only)*"
        if (@($Result.Shares).Count -eq 0) { & $w "*(none)*" }
        else {
            foreach ($sh in $Result.Shares) {
                & $w ""
                & $w "### ``$($sh.Name)`` — ``$($sh.Path)``"
                & $w "**Share permissions**"
                & $w ""
                if (@($sh.SharePermissions).Count -eq 0) { & $w "*(none)*" }
                else {
                    & $w "| Account | Right | Type |"
                    & $w "|---|---|---|"
                    foreach ($sp in $sh.SharePermissions) { & $w "| ``$($sp.Account)`` | $($sp.AccessRight) | $($sp.AccessControlType) |" }
                }
                & $w ""
                & $w "**NTFS ($($sh.NtfsPermissions.Depth))**"
                & $w ""
                if (@($sh.NtfsPermissions.Entries).Count -eq 0) { & $w "*(none)*" }
                else {
                    & $w "| Path | Account | Rights | Inherited | AppliesTo | Type |"
                    & $w "|---|---|---|---|---|---|"
                    foreach ($e in $sh.NtfsPermissions.Entries) { & $w "| ``$($e.Path)`` | ``$($e.Account)`` | $($e.Rights) | $(if ($e.Inherited) { 'Yes' } else { 'No' }) | $($e.AppliesTo) | $($e.AccessControlType) |" }
                }
            }
        }
        & $renderInlineFor 'Shares'
    }

    # Scheduled Tasks
    if (& $isCollected 'ScheduledTasks') {
        & $w ""
        & $w "## Scheduled Tasks *(custom only)*"
        if (@($Result.ScheduledTasks).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Path | Name | State | RunAs | Trigger | Action |"
            & $w "|---|---|---|---|---|---|"
            foreach ($t in $Result.ScheduledTasks) {
                $trig = ($t.Triggers -join '; ')
                $act  = ($t.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)".Trim() }) -join '; '
                & $w "| ``$($t.TaskPath)`` | $($t.TaskName) | $($t.State) | ``$($t.RunAs)`` | $trig | ``$act`` |"
            }
        }
        & $renderInlineFor 'ScheduledTasks'
    }

    # Service Accounts (auto-follows Services/ScheduledTasks/Iis)
    if (('Services' -in $collected) -or ('ScheduledTasks' -in $collected) -or ('Iis' -in $collected)) {
        & $w ""
        & $w "## Domain Service Accounts *(cross-cutting)*"
        if (@($Result.ServiceAccounts).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Account | Type | Used by |"
            & $w "|---|---|---|"
            foreach ($a in $Result.ServiceAccounts) {
                $used = ($a.UsedBy | ForEach-Object {
                    switch ($_.Kind) {
                        'Service'       { "Service: $($_.Name)" }
                        'ScheduledTask' { "ScheduledTask: $($_.Path)" }
                        'IISAppPool'    { "IISAppPool: $($_.Name)" }
                        default         { $_.Kind }
                    }
                }) -join '; '
                & $w "| ``$($a.Account)`` | $($a.Type) | $used |"
            }
        }
    }

    # Local Users
    if (& $isCollected 'LocalUsers') {
        & $w ""
        & $w "## Local Users *(non-standard only)*"
        if (@($Result.LocalUsers).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Name | Enabled | Password last set | PW never expires | Description |"
            & $w "|---|---|---|---|---|"
            foreach ($u in $Result.LocalUsers) { & $w "| $($u.Name) | $($u.Enabled) | $($u.PasswordLastSetUtc) | $($u.PasswordNeverExpires) | $($u.Description) |" }
        }
        & $renderInlineFor 'LocalUsers'
    }

    # Firewall
    if (& $isCollected 'FirewallRules') {
        & $w ""
        & $w "## Firewall *(non-standard, enabled only)*"
        if (@($Result.FirewallRules).Count -eq 0) { & $w "*(none)*" }
        else {
            & $w "| Rule | Direction | Action | Protocol | Port | Program | Profile |"
            & $w "|---|---|---|---|---|---|---|"
            foreach ($r in $Result.FirewallRules) { & $w "| $($r.DisplayName) | $($r.Direction) | $($r.Action) | $($r.Protocol) | $($r.LocalPort) | ``$($r.Program)`` | $($r.Profile) |" }
        }
        & $renderInlineFor 'FirewallRules'
    }

    # IIS
    if (& $isCollected 'Iis') {
        & $w ""
        & $w "## IIS"
        if (-not $Result.Iis) { & $w "*(not installed)*" }
        else {
            & $w "**Sites**"
            & $w ""
            if (@($Result.Iis.Sites).Count -eq 0) { & $w "*(none)*" }
            else {
                & $w "| Site | State | Bindings | Physical path |"
                & $w "|---|---|---|---|"
                foreach ($s in $Result.Iis.Sites) {
                    $b = ($s.Bindings | ForEach-Object {
                        $cert = if ($_.CertificateThumbprint) { " (cert ``$($_.CertificateThumbprint)``)" } else { '' }
                        "$($_.Protocol)://$($_.BindingInformation)$cert"
                    }) -join '; '
                    & $w "| $($s.Name) | $($s.State) | $b | ``$($s.PhysicalPath)`` |"
                }
            }
            & $w ""
            & $w "**App Pools**"
            & $w ""
            if (@($Result.Iis.AppPools).Count -eq 0) { & $w "*(none)*" }
            else {
                & $w "| Pool | State | Runtime | Identity |"
                & $w "|---|---|---|---|"
                foreach ($p in $Result.Iis.AppPools) {
                    $id = if ($p.Username) { $p.Username } else { $p.IdentityType }
                    & $w "| $($p.Name) | $($p.State) | $($p.ManagedRuntimeVersion) ($($p.ManagedPipelineMode)) | ``$id`` |"
                }
            }
        }
        & $renderInlineFor 'Iis'
    }

    # Installed Applications
    if (& $isCollected 'InstalledApplications') {
        & $w ""
        & $w "## Installed Applications *($(@($Result.InstalledApplications).Count))*"
        if (@($Result.InstalledApplications).Count -gt 0) {
            & $w "| Name | Version | Publisher | Install date | Source |"
            & $w "|---|---|---|---|---|"
            foreach ($a in $Result.InstalledApplications) { & $w "| $($a.DisplayName) | $($a.Version) | $($a.Publisher) | $($a.InstallDateUtc) | $($a.Source) |" }
        }
        & $renderInlineFor 'InstalledApplications'
    }

    # Chocolatey
    if (& $isCollected 'ChocolateyPackages') {
        & $w ""
        & $w "## Chocolatey Packages *($(@($Result.ChocolateyPackages).Count))*"
        if (@($Result.ChocolateyPackages).Count -gt 0) {
            & $w "| Id | Version |"
            & $w "|---|---|"
            foreach ($c in $Result.ChocolateyPackages) { & $w "| $($c.Id) | $($c.Version) |" }
        }
        & $renderInlineFor 'ChocolateyPackages'
    }

    # Windows Features
    if (& $isCollected 'WindowsFeatures') {
        & $w ""
        & $w "## Windows Features *($(@($Result.WindowsFeatures).Count))*"
        if (@($Result.WindowsFeatures).Count -gt 0) {
            & $w "| Name | DisplayName |"
            & $w "|---|---|"
            foreach ($f in $Result.WindowsFeatures) { & $w "| $($f.Name) | $($f.DisplayName) |" }
        }
        & $renderInlineFor 'WindowsFeatures'
    }

    # Certificates
    if (& $isCollected 'Certificates') {
        & $w ""
        & $w "## Certificates"
        if (@($Result.Certificates).Count -eq 0) { & $w "*(none)*" }
        else {
            $byStore = $Result.Certificates | Group-Object Store
            foreach ($g in $byStore) {
                & $w ""
                & $w "### ``$($g.Name)``"
                & $w "| Subject | Used for | Issuer | Thumbprint | Not after | Expires in | HasKey |"
                & $w "|---|---|---|---|---|---|---|"
                foreach ($c in $g.Group) {
                    $warn = if ($c.DaysUntilExpiry -le 90 -and -not $c.Expired) { "$([char]0x26A0) " } elseif ($c.Expired) { "$([char]0x274C) " } else { '' }
                    # "Used for": prefer FriendlyName, else fall back to the SAN DNS list.
                    $usedFor = if (-not [string]::IsNullOrWhiteSpace($c.FriendlyName)) {
                        $c.FriendlyName
                    } elseif (@($c.SubjectAlternativeNames).Count -gt 0) {
                        @($c.SubjectAlternativeNames) -join ', '
                    } else { '' }
                    & $w "| $($c.Subject) | $usedFor | $($c.Issuer) | ``$($c.Thumbprint)`` | $($c.NotAfterUtc) | $warn$($c.DaysUntilExpiry) d | $($c.HasPrivateKey) |"
                }
            }
        }
        & $renderInlineFor 'Certificates'
    }

    # Pending Reboot
    if (& $isCollected 'PendingReboot') {
        & $w ''
        & $w '## Pending Reboot'
        $pr = $Result.PendingReboot
        if ($null -eq $pr) { & $w '*(not collected)*' }
        else {
            & $w "**Any pending:** $($pr.Any)"
            & $w ''
            & $w '| Source | Pending |'
            & $w '|---|---|'
            foreach ($p in 'ComponentBasedServicing','WindowsUpdate','PendingFileRenameOps','ComputerNameChange','CcmClientSDK') {
                $val = $pr.$p
                $cell = if ($val) { [char]0x2705 } else { [char]0x274C }
                & $w "| $p | $cell |"
            }
            & $renderInlineFor 'PendingReboot'
        }
    }

    # Power Plan
    if (& $isCollected 'PowerPlan') {
        & $w ''
        & $w '## Power Plan'
        $pp = $Result.PowerPlan
        if ($null -eq $pp) { & $w '*(not collected)*' }
        else {
            & $w "**Active scheme:** $($pp.ActiveSchemeName) (``$($pp.ActiveSchemeGuid)``)"
            & $w ''
            & $w '| Scheme | GUID | Active |'
            & $w '|---|---|---|'
            foreach ($s in @($pp.AvailableSchemes)) {
                $a = if ($s.IsActive) { [char]0x2705 } else { '' }
                & $w "| $($s.Name) | ``$($s.Guid)`` | $a |"
            }
            & $renderInlineFor 'PowerPlan'
        }
    }

    # Page File
    if (& $isCollected 'PageFile') {
        & $w ''
        & $w '## Page File'
        $pf = $Result.PageFile
        if ($null -eq $pf) { & $w '*(not collected)*' }
        else {
            & $w "**Automatic management:** $($pf.AutomaticManagedPagefile)"
            if (@($pf.PageFiles).Count -gt 0) {
                & $w ''
                & $w '| Path | Initial MB | Max MB | Allocated MB | Peak MB | Current MB |'
                & $w '|---|---:|---:|---:|---:|---:|'
                foreach ($p in $pf.PageFiles) { & $w "| ``$($p.Path)`` | $($p.InitialMB) | $($p.MaximumMB) | $($p.AllocatedMB) | $($p.PeakMB) | $($p.CurrentMB) |" }
            }
            if ($pf.CrashControl) {
                & $w ''
                & $w '**Crash dump:**'
                $dedicatedStr = if ([string]::IsNullOrWhiteSpace($pf.CrashControl.DedicatedDumpFile)) { '*(none)*' } else { "``$($pf.CrashControl.DedicatedDumpFile)``" }
                & $w "- Mode: $($pf.CrashControl.CrashDumpEnabled)  ·  File: ``$($pf.CrashControl.DumpFile)``  ·  Dedicated: $dedicatedStr"
                & $w "- Overwrite: $($pf.CrashControl.Overwrite)  ·  AutoReboot: $($pf.CrashControl.AutoReboot)"
            }
            & $renderInlineFor 'PageFile'
        }
    }

    # TLS / SChannel
    if (& $isCollected 'Tls') {
        & $w ''
        & $w '## TLS / SChannel'
        $tls = $Result.Tls
        if ($null -eq $tls) { & $w '*(not collected)*' }
        else {
            & $w '| Protocol | Side | Enabled | DisabledByDefault |'
            & $w '|---|---|---|---|'
            foreach ($p in @($tls.Protocols)) {
                $e = if ($p.Enabled)           { [char]0x2705 } else { [char]0x274C }
                $d = if ($p.DisabledByDefault) { [char]0x2705 } else { [char]0x274C }
                & $w "| $($p.Name) | $($p.Side) | $e | $d |"
            }
            & $renderInlineFor 'Tls'
        }
    }

    if (& $isCollected 'Smb') {
        & $w ''
        & $w '## SMB'
        $smb = $Result.Smb
        if ($null -eq $smb) { & $w '*(not collected)*' }
        else {
            $bool = { param($v) if ($null -eq $v) { '?' } elseif ($v) { [char]0x2705 } else { [char]0x274C } }
            & $w '| Setting | Value |'
            & $w '|---|---|'
            & $w "| SMB1 enabled        | $(& $bool $smb.Smb1Enabled) |"
            & $w "| SMB2 enabled        | $(& $bool $smb.Smb2Enabled) |"
            & $w "| Signing required    | $(& $bool $smb.SigningRequired) |"
            & $w "| Signing enabled     | $(& $bool $smb.SigningEnabled) |"
            & $w "| Encrypt data        | $(& $bool $smb.EncryptData) |"
            & $w "| Reject unencrypted  | $(& $bool $smb.RejectUnencryptedAccess) |"
            & $w "| Audit SMB1 access   | $(& $bool $smb.AuditSmb1Access) |"
            & $w "| SMB1 client feature | $(& $bool $smb.Smb1ClientInstalled) |"
            & $renderInlineFor 'Smb'
        }
    }

    if (& $isCollected 'Defender') {
        & $w ''
        & $w '## Microsoft Defender'
        $def = $Result.Defender
        if ($null -eq $def) { & $w '*(not collected)*' }
        else {
            $bool = { param($v) if ($null -eq $v) { '?' } elseif ($v) { [char]0x2705 } else { [char]0x274C } }
            & $w '### Engine'
            & $w '| Setting | Value |'
            & $w '|---|---|'
            & $w "| Antivirus enabled            | $(& $bool $def.Engine.AntivirusEnabled) |"
            & $w "| Real-time protection enabled | $(& $bool $def.Engine.RealTimeProtectionEnabled) |"
            & $w "| Tamper protected             | $(& $bool $def.Engine.TamperProtected) |"
            & $w "| AM service enabled           | $(& $bool $def.Engine.AMServiceEnabled) |"
            & $w "| Signatures last updated UTC  | $($def.Engine.AntivirusSignatureLastUpdatedUtc) |"
            & $w "| Signature age (days)         | $($def.Engine.AntivirusSignatureAgeDays) |"
            & $w ''
            & $w '### Exclusions'
            & $w ''
            foreach ($exclGroup in @(
                @{ Label = 'Paths';      Items = @($def.Exclusions.Paths) },
                @{ Label = 'Extensions'; Items = @($def.Exclusions.Extensions) },
                @{ Label = 'Processes';  Items = @($def.Exclusions.Processes) }
            )) {
                $items = $exclGroup.Items
                if ($items.Count -gt 0) {
                    & $w "**$($exclGroup.Label)** ($($items.Count))"
                    foreach ($item in $items) { & $w "- ``$item``" }
                } else {
                    & $w "**$($exclGroup.Label)** *(none)*"
                }
                & $w ''
            }
            & $renderInlineFor 'Defender'
        }
    }

    if (& $isCollected 'UserRightsAssignment') {
        & $w ''
        & $w '## User Rights Assignment'
        $ura = @($Result.UserRightsAssignment)
        if ($ura.Count -eq 0) { & $w '*(not collected)*' }
        else {
            $uraIncludeAll = $Result.PSObject.Properties['UserRightsAssignmentIncludeAll'] -and $Result.UserRightsAssignmentIncludeAll
            $uraExpandMembers = $Result.PSObject.Properties['UserRightsExpandMembers'] -and $Result.UserRightsExpandMembers
            if (-not $uraIncludeAll) {
                & $w '*(non-default principals only — pass `-IncludeAllUserRights` to see all)*'
            }
            if (-not $uraExpandMembers) {
                & $w '*(pass `-ExpandUserRightsMembers` to see recursive user-only expansion under each privilege)*'
            }
            foreach ($r in $ura) {
                & $w ''
                & $w "### $($r.Privilege)"
                if (@($r.Principals).Count -eq 0) { & $w '*(none)*'; continue }
                & $w '| Account | Type | DistinguishedName |'
                & $w '|---|---|---|'
                foreach ($p in $r.Principals) { & $w "| ``$($p.Account)`` | $($p.Type) | $($p.DistinguishedName) |" }

                # Effective members block — only when expansion was requested AND members are present
                $expandFlag = $Result.PSObject.Properties['UserRightsExpandMembers'] -and $Result.UserRightsExpandMembers
                $principalsWithMembers = @($r.Principals | Where-Object { $_.PSObject.Properties['Members'] -and @($_.Members).Count -gt 0 })
                if ($expandFlag -and $principalsWithMembers.Count -gt 0) {
                    & $w ''
                    & $w '#### Effective members'
                    # De-dup + path-join (same algorithm as Permissions effective-members block).
                    # Guard against null/empty keys — URA local-group members can come back
                    # from the ADSI fallback with neither SID nor Account (fully unresolvable).
                    $effective = [ordered]@{}
                    $upsert = {
                        param($key, $row, $viaPath)
                        if ([string]::IsNullOrWhiteSpace([string]$key)) { return }
                        if ($effective.Contains($key)) {
                            if ($effective[$key].Paths -notcontains $viaPath) {
                                $effective[$key].Paths = @($effective[$key].Paths) + $viaPath
                            }
                        } else {
                            $row | Add-Member -NotePropertyName Paths -NotePropertyValue @($viaPath) -Force
                            $effective[$key] = $row
                        }
                    }
                    foreach ($p in $r.Principals) {
                        if ($p.PSObject.Properties['Members'] -and @($p.Members).Count -gt 0) {
                            foreach ($m in @($p.Members)) {
                                $viaPath = if (@($m.Path).Count -gt 0) { @($m.Path) -join ' → ' } else { $p.Account }
                                $keyM = if ($m.Sid) { $m.Sid } else { $m.Account }
                                $row = [pscustomobject]@{
                                    Account = $m.Account; Type = $m.Type
                                    Name = $m.Name; Domain = $m.Domain
                                    DistinguishedName = $m.DistinguishedName
                                }
                                & $upsert $keyM $row $viaPath
                            }
                        }
                    }
                    & $w '| Account | Domain | Type | Name | DistinguishedName | Inherited via |'
                    & $w '|---|---|---|---|---|---|'
                    foreach ($e in ($effective.Values | Sort-Object Account)) {
                        $via = @($e.Paths) -join ' ; '
                        & $w "| ``$($e.Account)`` | $($e.Domain) | $($e.Type) | $($e.Name) | $($e.DistinguishedName) | $via |"
                    }
                }
            }
            & $renderInlineFor 'UserRightsAssignment'
        }
    }

    # Chef
    if (& $isCollected 'Chef') {
        & $w ""
        & $w "## Chef"
        if (-not $Result.Chef) { & $w "*(not installed)*" }
        else {
            $c = $Result.Chef
            $dot = [char]0x00B7
            & $w "**Node:** $($c.NodeName)  $dot  **Environment:** $($c.Environment)  $dot  **Version:** $($c.Version)"
            & $w "**Chef Server:** $($c.ChefServerUrl)"
            if ($c.LastSuccessfulRunUtc) { & $w "**Last Successful Run (UTC):** $($c.LastSuccessfulRunUtc)" }
            & $w ""
            $runListHeader = "### Run List"
            if ($c.RunListSource) { $runListHeader += " *(source: $($c.RunListSource))*" }
            & $w $runListHeader
            if (@($c.RunList).Count -gt 0) {
                foreach ($r in $c.RunList) { & $w "- $r" }
            } else {
                & $w "*(empty)*"
                if ($c.ClientLogStatus -and $c.ClientLogStatus -ne 'OK') {
                    $logPathStr = if ($c.ClientLogPath) { " ($($c.ClientLogPath))" } else { '' }
                    & $w ""
                    & $w "> Client log probe: $($c.ClientLogStatus)$logPathStr"
                }
            }
            & $w ""
            $attrHeader = "### Attribute Keys"
            if ($c.AttributeSource) { $attrHeader += " *(source: $($c.AttributeSource))*" }
            & $w $attrHeader
            if ($c.AttributeStatus -and $c.AttributeStatus -ne 'OK') {
                $reason = switch ($c.AttributeStatus) {
                    'NoCacheFile'     { 'no node cache file under C:\chef\cache\nodes — server has not cached attributes locally' }
                    'CacheUnreadable' { "cache file present ($($c.AttributeCachePath)) but could not be parsed" }
                    default           { $c.AttributeStatus }
                }
                & $w "*(unavailable: $reason)*"
            } else {
                & $w "| Tree | Top-level keys |"
                & $w "|---|---|"
                foreach ($tree in 'default','normal','override','automatic') {
                    $keys = @($c.AttributeKeys.$tree)
                    $val  = if ($keys.Count -gt 0) { $keys -join ', ' } else { '*(none)*' }
                    & $w "| $tree | $val |"
                }
            }
        }
        & $renderInlineFor 'Chef'
    }

    # SQL Server — section is omitted entirely when SQL is not installed,
    # rather than printing an empty "*(not installed)*" stub. Detection ran;
    # absence is the answer.
    if ((& $isCollected 'SqlServer') -and -not ($null -eq $Result.SqlServer -or @($Result.SqlServer).Count -eq 0)) {
        & $w ""
        & $w "## SQL Server"
        foreach ($inst in @($Result.SqlServer)) {
            & $w ""
            [void]$sb.Append((Format-SqlServerInstanceBlock -Instance $inst))
        }
        & $renderInlineFor 'SqlServer'
    }

    # Errors (always rendered)
    & $w ""
    & $w "## Errors / Warnings"
    if (@($Result.Errors).Count -eq 0) { & $w "*(none)*" }
    else {
        foreach ($e in $Result.Errors) { & $w "- **$($e.Section):** $($e.Message)" }
    }

    return $sb.ToString()
}
