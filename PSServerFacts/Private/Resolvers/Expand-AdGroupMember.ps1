function ConvertTo-DomainFqdnFromDn {
    # Pull the DC= components out of a distinguished name and join them into
    # an FQDN. Used to discover a member's actual home domain — Get-ADGroupMember
    # returns cross-trust members with their real DN, but the parent's netbios
    # is the wrong source for the member's Account / domain attribution.
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][AllowNull()][string]$Dn)
    if ([string]::IsNullOrWhiteSpace($Dn)) { return $null }
    $parts = [regex]::Matches($Dn, '(?i)DC=([^,]+)') | ForEach-Object { $_.Groups[1].Value }
    if ($parts.Count -eq 0) { return $null }
    ($parts -join '.').ToLowerInvariant()
}

function Get-NetbiosFromFqdn {
    # Reverse-walk a netbios → FQDN cache to find the netbios for a given FQDN.
    # Returns $null when not found — callers fall back to the parent's netbios.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][AllowNull()][string]$Fqdn,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    if ([string]::IsNullOrWhiteSpace($Fqdn)) { return $null }
    $target = $Fqdn.ToUpperInvariant()
    foreach ($k in @($Cache.Keys)) {
        $v = $Cache[$k]
        if ($null -ne $v -and ([string]$v).ToUpperInvariant() -eq $target) {
            return [string]$k
        }
    }
    return $null
}

function Expand-AdGroupMember {
    # Recursively walk the membership of an AD group, emitting one row per
    # nested group and per leaf principal. Each emitted entry carries:
    #   * Sid / SamAccountName / Name / DistinguishedName from AD
    #   * Domain  — FQDN of the principal's home domain (derived from its DN,
    #     so cross-trust members are attributed correctly)
    #   * Account — DOMAIN\sam form (NetBIOS resolved from DomainCache when
    #     possible; falls back to the parent group's netbios when the
    #     member's home domain isn't in the cache)
    #   * Path    — chain of group accounts from outermost down to (but not
    #     including) this row, so reports can show "inherited via X → Y → Z"
    #
    # We deliberately do NOT pass -Recursive to Get-ADGroupMember. -Recursive
    # silently flattens in-forest nested groups, hiding intermediate groups
    # in the chain. By listing direct members only and recursing ourselves,
    # every level of nesting shows up in Path. The Visited set guards against
    # cycles. -SkipDefaultGroupExpansion stops recursion through huge well-
    # known groups (Domain Admins, etc.); the group entry is still emitted.
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][hashtable]$DomainCache,
        [switch]$SkipDefaultGroupExpansion,
        [hashtable]$Visited = @{},
        [string[]]$Chain = @(),
        # Optional FQDN(upper) → PSCredential map. Domains in the map use that
        # credential for AD calls instead of current Kerberos — see
        # Resolve-AdPrincipal for the cross-domain contract.
        [hashtable]$CredentialMap = @{}
    )

    if ($Visited.ContainsKey($Sid)) { return @() }
    $Visited[$Sid] = $true

    $netbios = ($Account -split '\\', 2)[0]
    $fqdn    = Resolve-DomainFqdn -NetbiosName $netbios -Cache $DomainCache
    if (-not $fqdn) { return @() }

    $newChain = @($Chain) + @($Account)

    $credKey = $fqdn.ToUpperInvariant()
    $adArgs  = @{ Server = $fqdn; ErrorAction = 'Stop' }
    if ($CredentialMap -and $CredentialMap.ContainsKey($credKey)) {
        $adArgs['Credential'] = $CredentialMap[$credKey]
    }

    # Resolve the group's DN by SID. Get-ADGroupMember -Identity does not
    # reliably accept raw SID strings; Get-ADObject's -Properties does not
    # expose 'SID' (only ObjectSID), and asking for it crashes the call.
    $grpObj = $null
    try {
        $grpObj = Get-ADObject -Filter "objectSID -eq '$Sid'" -Properties DistinguishedName @adArgs |
            Select-Object -First 1
    } catch { }
    if (-not $grpObj) {
        try {
            $sidObj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $grpObj = Get-ADObject -Identity $sidObj -Properties DistinguishedName @adArgs
        } catch { }
    }
    if (-not $grpObj) { return @() }

    try {
        $members = @(Get-ADGroupMember -Identity $grpObj.DistinguishedName @adArgs)
    } catch {
        return @()
    }

    $rows = foreach ($m in $members) {
        $memberSid = if ($m.SID) { [string]$m.SID.Value } else { $null }
        $memberSam = if ($m.PSObject.Properties['SamAccountName']) { [string]$m.SamAccountName } else { $null }

        $memberFqdn    = ConvertTo-DomainFqdnFromDn -Dn ([string]$m.DistinguishedName)
        $memberNetbios = Get-NetbiosFromFqdn -Fqdn $memberFqdn -Cache $DomainCache
        if (-not $memberNetbios) { $memberNetbios = $netbios }
        $memberAcc = if ($memberSam) { "$memberNetbios\$memberSam" } else { $memberSid }

        if ($m.ObjectClass -eq 'group' -and $memberSid -and -not $Visited.ContainsKey($memberSid)) {
            $groupRow = [pscustomobject]@{
                Sid = $memberSid; Account = $memberAcc; Type = 'Group'
                SamAccountName = $memberSam
                Name = $m.Name
                DistinguishedName = $m.DistinguishedName
                Domain = $memberFqdn
                Path = $newChain
                Skipped = $false
            }

            if ($SkipDefaultGroupExpansion -and (Test-IsDefaultGroupSid -Sid $memberSid)) {
                $groupRow.Skipped = $true
                $groupRow
                continue
            }
            $groupRow
            Expand-AdGroupMember -Sid $memberSid -Account $memberAcc -DomainCache $DomainCache `
                -SkipDefaultGroupExpansion:$SkipDefaultGroupExpansion -Visited $Visited -Chain $newChain `
                -CredentialMap $CredentialMap
            continue
        }

        $type = switch ($m.ObjectClass) {
            'user'                            { if ("$memberAcc".EndsWith('$')) { 'gMSA' } else { 'User' } }
            'msDS-GroupManagedServiceAccount' { 'gMSA' }
            'computer'                        { 'Computer' }
            'group'                           { 'Group' }
            default                           { 'User' }
        }

        [pscustomobject]@{
            Sid = $memberSid; Account = $memberAcc; Type = $type
            SamAccountName = $memberSam
            Name = $m.Name
            DistinguishedName = $m.DistinguishedName
            Domain = $memberFqdn
            Path = $newChain
            Skipped = $false
        }
    }

    @($rows)
}
