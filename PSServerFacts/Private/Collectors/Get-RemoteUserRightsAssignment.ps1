function Get-RemoteUserRightsAssignment {
    # On the target session: run `secedit /export /cfg <tmp>`, read the INF,
    # filter to the [Privilege Rights] block, transmit lines back. Jumphost
    # side: parse "SeXxx = *S-1-…,*S-1-…" and resolve each SID via the
    # existing Resolve-AdPrincipal (which uses $DomainCache).
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][hashtable]$DomainCache,
        [switch]$ExpandMembers,
        # FQDN(upper) → PSCredential map for cross-domain / cross-forest resolution.
        # Forwarded as -CredentialMap to Resolve-AdPrincipal.
        [hashtable]$DomainCredential = @{}
    )

    $tracked = @(
        'SeTcbPrivilege','SeBackupPrivilege','SeRestorePrivilege','SeDebugPrivilege',
        'SeServiceLogonRight','SeBatchLogonRight','SeInteractiveLogonRight',
        'SeRemoteInteractiveLogonRight','SeDenyInteractiveLogonRight',
        'SeDenyNetworkLogonRight','SeLoadDriverPrivilege','SeTakeOwnershipPrivilege',
        'SeAssignPrimaryTokenPrivilege','SeImpersonatePrivilege','SeShutdownPrivilege'
    )

    $lines = Invoke-Command -Session $Session -ArgumentList (,$tracked) -ScriptBlock {
        param([string[]]$Tracked)
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $null = secedit /export /cfg $tmp /quiet 2>$null
            if (-not (Test-Path $tmp)) { return @() }
            $content = Get-Content $tmp -ErrorAction Stop
            $inPriv = $false
            $out = New-Object System.Collections.Generic.List[string]
            foreach ($ln in $content) {
                if ($ln -match '^\[Privilege Rights\]') { $inPriv = $true; continue }
                if ($inPriv -and $ln -match '^\[') { break }
                if ($inPriv -and $ln -match '^([A-Za-z]+)\s*=\s*(.+)$') {
                    if ($Tracked -contains $matches[1]) { $out.Add($ln) | Out-Null }
                }
            }
            ,$out.ToArray()
        } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }

    $result = foreach ($ln in @($lines)) {
        if ($ln -notmatch '^([A-Za-z]+)\s*=\s*(.+)$') { continue }
        $priv = $matches[1]
        $rhs  = $matches[2].Trim()
        $sids = @($rhs -split ',' | ForEach-Object { ($_ -replace '^\*','').Trim() } | Where-Object { $_ })
        $principals = foreach ($sid in $sids) {
            try {
                $account = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value
            } catch { $account = $sid }
            Resolve-AdPrincipal -Sid $sid -Account $account -DomainCache $DomainCache -CredentialMap $DomainCredential
        }
        [pscustomobject]@{ Privilege = $priv; Principals = @($principals) }
    }
    $result = @($result)

    if (-not $ExpandMembers) { return $result }

    # Second pass: collect distinct BUILTIN\ groups referenced across all privileges,
    # enumerate their members on the target (with ADSI WinNT fallback), resolve on jumphost,
    # attach as .Members on each matching Principal entry.
    $builtinGroups = @(
        $result | ForEach-Object { $_.Principals } |
        Where-Object { $_.Type -eq 'WellKnown' -and $_.Account -match '^BUILTIN\\' } |
        Select-Object -ExpandProperty Account -Unique
    )

    if ($builtinGroups.Count -gt 0) {
        # Get the short group names (strip "BUILTIN\") for Get-LocalGroupMember.
        $groupNames = @($builtinGroups | ForEach-Object { ($_ -split '\\',2)[1] })

        $rawMembersLookup = Invoke-Command -Session $Session -ArgumentList (,$groupNames) -ScriptBlock {
            param([string[]]$GroupNames)

            function Get-RawGroupMembers([string]$GroupName) {
                try {
                    $rows = Get-LocalGroupMember -Group $GroupName -ErrorAction Stop |
                        ForEach-Object { [pscustomobject]@{ Sid = $_.SID.Value; Account = $_.Name } }
                    return @($rows)
                } catch { }
                try {
                    $grp = [ADSI]("WinNT://./" + $GroupName + ",group")
                    $members = $grp.psbase.Invoke('Members')
                    $rows = foreach ($m in $members) {
                        $path = try { $m.GetType().InvokeMember('AdsPath','GetProperty',$null,$m,$null) } catch { $null }
                        $name = try { $m.GetType().InvokeMember('Name','GetProperty',$null,$m,$null) }    catch { $null }
                        $account = if ($path -match '^WinNT://([^/]+)/([^/]+)$') { "$($matches[1])\$($matches[2])" } else { $name }
                        $sid = $null
                        if ($account) {
                            try { $sid = (New-Object System.Security.Principal.NTAccount($account)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
                        }
                        if (-not $sid) {
                            try {
                                $raw = $m.GetType().InvokeMember('objectSid','GetProperty',$null,$m,$null)
                                if ($raw) {
                                    $byteArr = [byte[]]@($raw | ForEach-Object { [byte]$_ })
                                    $sid = (New-Object System.Security.Principal.SecurityIdentifier($byteArr, 0)).Value
                                }
                            } catch { }
                        }
                        if ([string]::IsNullOrWhiteSpace($account) -and [string]::IsNullOrWhiteSpace($sid)) { continue }
                        [pscustomobject]@{ Sid = $sid; Account = $account }
                    }
                    return @($rows)
                } catch { }
                return @()
            }

            $lookup = @{}
            foreach ($gn in $GroupNames) {
                $lookup[$gn] = @(Get-RawGroupMembers $gn)
            }
            $lookup
        }

        # Build a lookup keyed by "BUILTIN\<name>" -> resolved members
        $resolvedMembersLookup = @{}
        foreach ($groupName in $groupNames) {
            $builtinKey = "BUILTIN\$groupName"
            try {
                $rawList = @($rawMembersLookup[$groupName])
                $resolved = @(foreach ($raw in $rawList) {
                    if ([string]::IsNullOrWhiteSpace($raw.Sid) -and [string]::IsNullOrWhiteSpace($raw.Account)) { continue }
                    try {
                        $member = Resolve-AdPrincipal -Sid $raw.Sid -Account $raw.Account -DomainCache $DomainCache -CredentialMap $DomainCredential
                        # Attach Path for "Inherited via" rendering (top-level group is the path root)
                        $member | Add-Member -NotePropertyName Path -NotePropertyValue @($builtinKey) -Force
                        $member
                    } catch { }
                })
                $resolvedMembersLookup[$builtinKey] = $resolved
            } catch { }
        }

        # Attach .Members to each Principal entry that is a BUILTIN\ group
        foreach ($entry in $result) {
            foreach ($principal in $entry.Principals) {
                if ($principal.Type -eq 'WellKnown' -and $principal.Account -match '^BUILTIN\\') {
                    $members = if ($resolvedMembersLookup.ContainsKey($principal.Account)) {
                        $resolvedMembersLookup[$principal.Account]
                    } else { @() }
                    $principal | Add-Member -NotePropertyName Members -NotePropertyValue $members -Force
                }
            }
        }
    }

    $result
}
