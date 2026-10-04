function Get-ServerFacts {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential,
        [pscredential]$SqlCredential,
        [Parameter(Mandatory)][hashtable]$DomainCache,
        [Parameter(Mandatory)][hashtable]$DataFiles,
        [Parameter(Mandatory)][ValidateSet('Root','Children','Recursive')][string]$NtfsDepth,
        [Parameter(Mandatory)][ValidateSet('Auto','Install','None')][string]$NtfsSecurityProvisioning,
        [bool]$IncludeAllServices,
        [bool]$IncludeAllShares,
        [bool]$IncludeAllScheduledTasks,
        [bool]$IncludeAllCertStores,
        [bool]$IncludeAllFirewallRules,
        [bool]$IncludeBackupDirectoryRoot,
        [bool]$ExpandGroupMembers,
        [bool]$SkipDefaultGroupExpansion,
        [bool]$IncludeAllUserRights,
        [bool]$ExpandUserRightsMembers,
        [bool]$AdvisoryJson,
        [bool]$SkipAdvisories,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Section,
        # FQDN(upper) → PSCredential map. Forwarded to Resolve-AdPrincipal,
        # Expand-AdGroupMember, and Get-RemoteUserRightsAssignment so cross-domain
        # principal resolution can use a different account than the worker's
        # Kerberos context. Pre-populated and validated in Export-ServerFacts.
        [hashtable]$DomainCredential = @{}
    )

    $start  = Get-Date
    $errors = [System.Collections.Generic.List[object]]::new()

    $scannedBy = "$env:USERDOMAIN\$env:USERNAME"

    try {
        $invokeArgs = @{ ComputerName = $ComputerName }
        if ($Credential) { $invokeArgs['Credential'] = $Credential }

        # Capture both data and section errors from inside the session block.
        # Dynamic scoping does not reliably reach back into Get-ServerFacts's
        # local scope from inside Invoke-WithSession's invocation chain, so we
        # bundle errors with the data and merge them after.
        $bundle = Invoke-WithSession @invokeArgs -ScriptBlock {
            param($session)

            $r           = [ordered]@{}
            $sectionErrs = [System.Collections.Generic.List[object]]::new()

            function Run-Section {
                param([string]$Name,[scriptblock]$Body)
                try { return & $Body } catch {
                    $sectionErrs.Add([pscustomobject]@{ Section = $Name; Message = $_.Exception.Message }) | Out-Null
                    return $null
                }
            }

            if ('System'                -in $Section) { $r.System        = Run-Section 'System'          { Get-RemoteSystem               -Session $session } }
            if ('Hardware'              -in $Section) { $r.Hardware      = Run-Section 'Hardware'        { Get-RemoteHardware             -Session $session } }
            if ('Disks'                 -in $Section) { $r.Disks         = Run-Section 'Disks'           { Get-RemoteDisks                -Session $session } }
            if ('Network'               -in $Section) { $r.Network       = Run-Section 'Network'         { Get-RemoteNetwork              -Session $session } }
            if ('InstalledApplications' -in $Section) { $r.InstalledApps = Run-Section 'InstalledApps'   { Get-RemoteInstalledApplication -Session $session } }
            if ('ChocolateyPackages'    -in $Section) { $r.Choco         = Run-Section 'Chocolatey'      { Get-RemoteChocolateyPackage    -Session $session } }
            if ('WindowsFeatures'       -in $Section) { $r.Features      = Run-Section 'WindowsFeatures' { Get-RemoteWindowsFeature       -Session $session } }
            if ('Permissions'           -in $Section) { $r.PermRaw       = Run-Section 'Permissions'     { Get-RemotePermission           -Session $session } }
            if ('Services'              -in $Section) { $r.ServicesRaw   = Run-Section 'Services'        { Get-RemoteService              -Session $session } }
            if ('Shares'                -in $Section) { $r.SharesRaw     = Run-Section 'Shares'          { Get-RemoteShare                -Session $session -NtfsDepth $NtfsDepth -NtfsSecurityProvisioning $NtfsSecurityProvisioning } }
            if ('ScheduledTasks'        -in $Section) { $r.TasksRaw      = Run-Section 'ScheduledTasks'  { Get-RemoteScheduledTask        -Session $session } }
            if ('LocalUsers'            -in $Section) { $r.LocalUsers    = Run-Section 'LocalUsers'      { Get-RemoteLocalUser            -Session $session } }
            if ('FirewallRules'         -in $Section) { $r.FirewallRaw   = Run-Section 'FirewallRules'   { Get-RemoteFirewallRule         -Session $session } }
            if ('Iis'                   -in $Section) { $r.Iis           = Run-Section 'Iis'             { Get-RemoteIis                  -Session $session } }
            if ('Certificates'          -in $Section) { $r.Certs         = Run-Section 'Certificates'    { Get-RemoteCertificate          -Session $session -IncludeAllStores $IncludeAllCertStores } }
            if ('Chef'                  -in $Section) { $r.Chef          = Run-Section 'Chef'             { Get-RemoteChef                 -Session $session } }
            if ('SqlServer'             -in $Section) {
                $r.SqlServer = Run-Section 'SqlServer' {
                    $sqlArgs = @{ Session = $session; ComputerName = $ComputerName }
                    if ($r.Disks)       { $sqlArgs['Disks']         = $r.Disks }
                    if ($SqlCredential) { $sqlArgs['SqlCredential'] = $SqlCredential }
                    if ($IncludeBackupDirectoryRoot) { $sqlArgs['IncludeBackupDirectoryRoot'] = $true }
                    Get-RemoteSqlServer @sqlArgs
                }
                # Per-instance ConnectionError / LiveQueryError live inside the
                # returned object — surface them as section-level errors so the
                # summary's Errors column reflects reality.
                # Also expand AD groups in BackupDirectory ACEs to recursive members.
                foreach ($inst in @($r.SqlServer)) {
                    if ($null -eq $inst) { continue }
                    if ($inst.ConnectionError) {
                        $sectionErrs.Add([pscustomobject]@{ Section = "SqlServer/$($inst.InstanceName)"; Message = "Connect: $($inst.ConnectionError)" }) | Out-Null
                    }
                    if ($inst.LiveQueryError) {
                        $sectionErrs.Add([pscustomobject]@{ Section = "SqlServer/$($inst.InstanceName)"; Message = "LiveQuery: $($inst.LiveQueryError)" }) | Out-Null
                    }
                    foreach ($acl in @($inst.BackupDirectoryAcls)) {
                        if ($null -eq $acl -or $null -eq $acl.Entries) { continue }
                        foreach ($entry in @($acl.Entries)) {
                            if ([string]::IsNullOrWhiteSpace($entry.Account)) { continue }
                            $sid = $null
                            try { $sid = (New-Object System.Security.Principal.NTAccount($entry.Account)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
                            if (-not $sid) { continue }
                            try {
                                $principal = Resolve-AdPrincipal -Sid $sid -Account $entry.Account -DomainCache $DomainCache -CredentialMap $DomainCredential
                                $entry | Add-Member -NotePropertyName Principal -NotePropertyValue $principal -Force
                                if ($principal.Type -eq 'Group' -and $ExpandGroupMembers) {
                                    $isDefault = Test-IsDefaultGroupSid -Sid $sid
                                    $members = if ($SkipDefaultGroupExpansion -and $isDefault) { @() }
                                               else { @(Expand-AdGroupMember -Sid $sid -Account $entry.Account -DomainCache $DomainCache -SkipDefaultGroupExpansion:$SkipDefaultGroupExpansion -CredentialMap $DomainCredential) }
                                    $entry | Add-Member -NotePropertyName Members -NotePropertyValue $members -Force
                                    $entry | Add-Member -NotePropertyName MembersSkipped -NotePropertyValue ($SkipDefaultGroupExpansion -and $isDefault) -Force
                                } else {
                                    $entry | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                                }
                            } catch {
                                $sectionErrs.Add([pscustomobject]@{ Section = "SqlServer/$($inst.InstanceName)"; Message = "Backup ACL resolve failed for $($entry.Account): $($_.Exception.Message)" }) | Out-Null
                            }
                        }
                    }
                }
            }
            if ('PendingReboot'         -in $Section) { $r.PendingReboot          = Run-Section 'PendingReboot'          { Get-RemotePendingReboot            -Session $session } }
            if ('PowerPlan'             -in $Section) { $r.PowerPlan              = Run-Section 'PowerPlan'              { Get-RemotePowerPlan                -Session $session } }
            if ('PageFile'              -in $Section) { $r.PageFile               = Run-Section 'PageFile'               { Get-RemotePageFile                 -Session $session } }
            if ('Tls'                   -in $Section) { $r.Tls                    = Run-Section 'Tls'                    { Get-RemoteTls                      -Session $session } }
            if ('Smb'                   -in $Section) { $r.Smb                    = Run-Section 'Smb'                    { Get-RemoteSmb                      -Session $session } }
            if ('Defender'              -in $Section) { $r.Defender               = Run-Section 'Defender'               { Get-RemoteDefender                 -Session $session } }
            if ('UserRightsAssignment'  -in $Section) { $r.UserRightsAssignment   = Run-Section 'UserRightsAssignment'   { Get-RemoteUserRightsAssignment     -Session $session -DomainCache $DomainCache -ExpandMembers:$ExpandUserRightsMembers -DomainCredential $DomainCredential } }

            [pscustomobject]@{ Data = $r; SectionErrors = $sectionErrs }
        }

        $result = $bundle.Data
        foreach ($e in $bundle.SectionErrors) { $errors.Add($e) | Out-Null }

        $defServices = $DataFiles.DefaultServices
        $defShares   = $DataFiles.DefaultShares
        $defTasks    = $DataFiles.DefaultTaskPaths
        $defCert     = $DataFiles.DefaultCertIssuers
        $defFirewall = $DataFiles.DefaultFirewallGroupPrefixes

        # Helper: coerce possibly-null collector output into a real array,
        # stripping any embedded $null that might have come from a fault-tolerant section.
        $servicesRaw = @($result.ServicesRaw | Where-Object { $null -ne $_ })
        $sharesRawIn = @($result.SharesRaw   | Where-Object { $null -ne $_ })
        $tasksRawIn  = @($result.TasksRaw    | Where-Object { $null -ne $_ })
        $fwRawIn     = @($result.FirewallRaw | Where-Object { $null -ne $_ })
        $certsIn     = @($result.Certs       | Where-Object { $null -ne $_ })

        # Services filter
        $services = @(if ($IncludeAllServices) {
            $servicesRaw
        } else {
            $servicesRaw | Where-Object { -not (Test-IsDefaultService -Service $_ -KnownDefaults $defServices.KnownDefaults -KnownCustomFalsePositives $defServices.KnownCustomFalsePositives) }
        })

        # Shares filter + NTFS normalization
        $sharesRaw = @(if ($IncludeAllShares) {
            $sharesRawIn
        } else {
            $sharesRawIn | Where-Object { -not (Test-IsDefaultShare -Name $_.Name -DefaultNames $defShares.Names) }
        })
        $shares = @(foreach ($s in $sharesRaw) {
            $entries = @(foreach ($ace in $s.NtfsRawAces) {
                ConvertTo-NtfsPermissionEntry -Ace $ace -Path $ace._path -SourceKind $s.NtfsSourceKind
            })
            foreach ($e in $s.NtfsErrors) {
                $errors.Add([pscustomobject]@{ Section = 'Shares.NTFS'; Message = $e }) | Out-Null
            }
            [pscustomobject]@{
                Name             = $s.Name
                Path             = $s.Path
                Description      = $s.Description
                SharePermissions = @($s.SharePermissions)
                NtfsPermissions  = [pscustomobject]@{
                    Depth   = $NtfsDepth
                    Entries = $entries
                }
            }
        })

        # Scheduled tasks filter + trigger formatting
        $tasksFiltered = @(if ($IncludeAllScheduledTasks) {
            $tasksRawIn
        } else {
            $tasksRawIn | Where-Object { -not (Test-IsDefaultScheduledTask -TaskPath $_.TaskPath -Patterns $defTasks.Patterns) }
        })
        $tasks = @(foreach ($t in $tasksFiltered) {
            # Tasks with no triggers (on-demand only, or programmatically created
            # without one) come back with $t.Triggers = $null. ForEach-Object on
            # a null source still emits one $null, which Format-TriggerSummary
            # rejects via its [Parameter(Mandatory)] binder. Filter $null FIRST.
            # Each task is wrapped so one malformed trigger doesn't abort the
            # whole worker — degrade just this section instead.
            try {
                $triggers = @(@($t.Triggers) | Where-Object { $null -ne $_ } |
                              ForEach-Object { Format-TriggerSummary -Trigger $_ })
                [pscustomobject]@{
                    TaskPath = $t.TaskPath
                    TaskName = $t.TaskName
                    State    = $t.State
                    RunAs    = $t.RunAs
                    Triggers = $triggers
                    Actions  = @($t.Actions)
                }
            } catch {
                $errors.Add([pscustomobject]@{
                    Section = 'ScheduledTasks'
                    Message = "Normalize failed for $($t.TaskPath)$($t.TaskName): $($_.Exception.Message)"
                }) | Out-Null
            }
        })

        # Firewall filter
        $firewall = @(if ($IncludeAllFirewallRules) {
            $fwRawIn
        } else {
            $fwRawIn | Where-Object { -not (Test-IsDefaultFirewallRule -Group ([string]$_.Group) -GroupPrefixes $defFirewall.Prefixes) }
        })

        # Certificates filter — strip well-known issuers from the pre-seeded
        # Windows trust stores. LocalMachine\My (machine identity) is left
        # untouched: the certs there are real and worth seeing.
        $certs = @(if ($IncludeAllCertStores) {
            $certsIn
        } else {
            $certsIn | Where-Object {
                $store = $_.Store
                if ($store -in 'LocalMachine\Root','LocalMachine\CA','LocalMachine\TrustedPublisher') {
                    -not (Test-IsDefaultCertIssuer -Issuer $_.Issuer -DefaultIssuers $defCert.Issuers)
                } else { $true }
            }
        })

        # Permissions resolution. Top-level entries preserve the direct ACE/group
        # member shape (Type=Group stays Group, Type=User stays User). When
        # -ExpandGroupMembers is set, Group entries get an attached .Members
        # array with the recursive flat user list; -SkipDefaultGroupExpansion
        # stops recursion through Domain Admins / Domain Users / etc.
        # Each entry is wrapped so one bad principal can't abort the section.
        $resolved = [pscustomobject]@{
            Administrators        = @()
            RemoteDesktopUsers    = @()
            RemoteManagementUsers = @()
        }
        foreach ($groupName in 'Administrators','RemoteDesktopUsers','RemoteManagementUsers') {
            $raw = if ($result.PermRaw) { $result.PermRaw.$groupName } else { @() }
            $list = @(foreach ($entry in $raw) {
                if ([string]::IsNullOrWhiteSpace($entry.Sid)) {
                    $errors.Add([pscustomobject]@{ Section = "Permissions/$groupName"; Message = "No SID resolved for member: $($entry.Account)" }) | Out-Null
                    continue
                }
                try {
                    $p = Resolve-AdPrincipal -Sid $entry.Sid -Account $entry.Account -DomainCache $DomainCache -CredentialMap $DomainCredential
                    if ($p.Type -eq 'Group' -and $ExpandGroupMembers) {
                        $isDefault = Test-IsDefaultGroupSid -Sid $entry.Sid
                        if ($SkipDefaultGroupExpansion -and $isDefault) {
                            $p | Add-Member -NotePropertyName Members -NotePropertyValue @() -Force
                            $p | Add-Member -NotePropertyName MembersSkipped -NotePropertyValue $true -Force
                        } else {
                            $members = @(Expand-AdGroupMember -Sid $entry.Sid -Account $entry.Account -DomainCache $DomainCache -SkipDefaultGroupExpansion:$SkipDefaultGroupExpansion -CredentialMap $DomainCredential)
                            $p | Add-Member -NotePropertyName Members -NotePropertyValue $members -Force
                            $p | Add-Member -NotePropertyName MembersSkipped -NotePropertyValue $false -Force
                        }
                    }
                    $p
                } catch {
                    $errors.Add([pscustomobject]@{ Section = "Permissions/$groupName"; Message = "Resolve failed for $($entry.Account) ($($entry.Sid)): $($_.Exception.Message)" }) | Out-Null
                }
            })
            $resolved.$groupName = $list
        }

        # Service accounts cross-cut (auto-derives from Services + ScheduledTasks + Iis)
        $svcAccounts = ConvertTo-ServiceAccountList -Services $services -ScheduledTasks $tasks -Iis $result.Iis -Hostname $ComputerName

        $status = if ($errors.Count -gt 0) { 'PartialSuccess' } else { 'Success' }

        $out = [ordered]@{
            Computer          = $ComputerName
            ScannedAtUtc      = $start.ToUniversalTime().ToString('o')
            ScannedBy         = $scannedBy
            Status            = $status
            DurationSeconds   = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            CollectedSections = @($Section)
        }

        if ('System'                -in $Section) { $out.System                = $result.System }
        if ('Hardware'              -in $Section) { $out.Hardware              = $result.Hardware }
        if ('Disks'                 -in $Section) { $out.Disks                 = @($result.Disks) }
        if ('Network'               -in $Section) { $out.Network               = $result.Network }
        if ('InstalledApplications' -in $Section) { $out.InstalledApplications = @($result.InstalledApps) }
        if ('ChocolateyPackages'    -in $Section) { $out.ChocolateyPackages    = @($result.Choco) }
        if ('WindowsFeatures'       -in $Section) { $out.WindowsFeatures       = @($result.Features) }
        if ('Permissions'           -in $Section) { $out.Permissions           = $resolved }
        if ('Services'              -in $Section) { $out.Services              = @($services) }
        if ('Shares'                -in $Section) { $out.Shares                = @($shares) }
        if ('ScheduledTasks'        -in $Section) { $out.ScheduledTasks        = @($tasks) }
        if ('LocalUsers'            -in $Section) { $out.LocalUsers            = @($result.LocalUsers | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) }) }
        if ('FirewallRules'         -in $Section) { $out.FirewallRules         = @($firewall) }
        if ('Iis'                   -in $Section) { $out.Iis                   = $result.Iis }
        if ('Certificates'          -in $Section) { $out.Certificates          = @($certs) }
        if ('Chef'                  -in $Section) { $out.Chef                  = $result.Chef }
        if ('SqlServer'             -in $Section) { $out.SqlServer             = $result.SqlServer }
        if ('PendingReboot'         -in $Section) { $out.PendingReboot         = $result.PendingReboot }
        if ('PowerPlan'             -in $Section) { $out.PowerPlan             = $result.PowerPlan }
        if ('PageFile'              -in $Section) { $out.PageFile              = $result.PageFile }
        if ('Tls'                   -in $Section) { $out.Tls                   = $result.Tls }
        if ('Smb'                   -in $Section) { $out.Smb                   = $result.Smb }
        if ('Defender'              -in $Section) { $out.Defender              = $result.Defender }
        if ('UserRightsAssignment'  -in $Section) {
            $defaults = $DataFiles.DefaultUserRights.Defaults
            $ura = if ($IncludeAllUserRights) {
                @($result.UserRightsAssignment)
            } else {
                @(foreach ($entry in @($result.UserRightsAssignment)) {
                    $filtered = @($entry.Principals | Where-Object {
                        -not (Test-IsDefaultUserRightPrincipal -Privilege $entry.Privilege -Account $_.Account -Defaults $defaults)
                    })
                    if ($filtered.Count -eq 0) { continue }
                    [pscustomobject]@{ Privilege = $entry.Privilege; Principals = $filtered }
                })
            }
            $out.UserRightsAssignment = $ura
            $out.UserRightsAssignmentIncludeAll = $IncludeAllUserRights
            $out.UserRightsExpandMembers = $ExpandUserRightsMembers

            if ($ExpandUserRightsMembers) {
                $visitedCache = @{}
                foreach ($entry in $ura) {
                    foreach ($p in $entry.Principals) {
                        if (-not ($p.PSObject.Properties['Members'])) { continue }
                        $currentMembers = @($p.Members)
                        if ($currentMembers.Count -eq 0) { continue }
                        $leaves = New-Object System.Collections.Generic.List[object]
                        foreach ($m in $currentMembers) {
                            if ($m.Type -eq 'Group' -and $m.Sid) {
                                try {
                                    # -Chain is $m.Path (chain up to BUT NOT including
                                    # this group). Expand-AdGroupMember appends $m.Account
                                    # itself once internally — don't pre-append here or we
                                    # get a duplicated tail element in the rendered path.
                                    $expanded = @(Expand-AdGroupMember -Sid $m.Sid -Account $m.Account `
                                        -DomainCache $DomainCache `
                                        -SkipDefaultGroupExpansion:$SkipDefaultGroupExpansion `
                                        -Visited $visitedCache `
                                        -Chain $m.Path `
                                        -CredentialMap $DomainCredential)
                                    foreach ($leaf in $expanded) {
                                        if ($leaf.Type -ne 'Group') { $leaves.Add($leaf) | Out-Null }
                                    }
                                } catch {
                                    $leaves.Add($m) | Out-Null
                                }
                            } elseif ($m.Type -ne 'Group') {
                                $leaves.Add($m) | Out-Null
                            }
                        }
                        # NOTE: $leaves is a List[object]. @($leaves) trips a
                        # PowerShell-internal "Argument types do not match" on
                        # lists containing pscustomobjects. .ToArray() works.
                        $p | Add-Member -NotePropertyName Members -NotePropertyValue $leaves.ToArray() -Force
                    }
                }
            }
        }

        # ServiceAccounts auto-derives if any of its source sections are present
        if ('Services' -in $Section -or 'ScheduledTasks' -in $Section -or 'Iis' -in $Section) {
            $out.ServiceAccounts = @($svcAccounts)
        }

        $out.Errors = @($errors)

        $resultObj = [pscustomobject]$out

        if (-not $SkipAdvisories) {
            $roles      = Get-ServerRoleFlag -Result $resultObj
            $advisories = @(
                Test-PendingRebootAdvisory -Result $resultObj -Roles $roles
                Test-PowerPlanAdvisory     -Result $resultObj -Roles $roles
                Test-PageFileAdvisory      -Result $resultObj -Roles $roles
                Test-TlsAdvisory           -Result $resultObj -Roles $roles
                Test-SmbAdvisory           -Result $resultObj -Roles $roles
                Test-DefenderAdvisory      -Result $resultObj -Roles $roles
                Test-UserRightsAdvisory    -Result $resultObj -Roles $roles
                Test-SystemAdvisory        -Result $resultObj -Roles $roles
            )
            $sorted = @($advisories | Sort-Object @{Expression={
                switch ($_.Severity) { 'Critical'{0} 'Warning'{1} 'Note'{2} default{3} }
            }}, 'Section', 'Rule')
            $resultObj | Add-Member -NotePropertyName AdvisoriesComputed -NotePropertyValue $sorted -Force
            if ($AdvisoryJson) {
                $resultObj | Add-Member -NotePropertyName Advisories -NotePropertyValue $sorted -Force
            }
        }

        $resultObj
    } catch {
        $errors.Add([pscustomobject]@{ Section = 'Connect'; Message = $_.Exception.Message }) | Out-Null
        [pscustomobject]@{
            Computer          = $ComputerName
            ScannedAtUtc      = $start.ToUniversalTime().ToString('o')
            ScannedBy         = $scannedBy
            Status            = 'Failed'
            DurationSeconds   = [math]::Round(((Get-Date) - $start).TotalSeconds, 1)
            CollectedSections = @()
            Errors            = @($errors)
        }
    }
}
