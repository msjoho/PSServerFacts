# Stubs so Pester Mock has a target when the ActiveDirectory module isn't loaded
# (e.g. unit tests or hosts without RSAT). The real cmdlets shadow these once
# the ActiveDirectory module is imported.
if (-not (Get-Command Get-ADObject -ErrorAction SilentlyContinue)) {
    function Get-ADObject {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)]$Identity,
            [string]$Filter,
            $Server,
            $Properties,
            [pscredential]$Credential
        )
        throw "ActiveDirectory module is not loaded; install RSAT or import ActiveDirectory."
    }
}
if (-not (Get-Command Get-ADGroupMember -ErrorAction SilentlyContinue)) {
    function Get-ADGroupMember {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)]$Identity,
            $Server,
            [switch]$Recursive,
            [pscredential]$Credential
        )
        throw "ActiveDirectory module is not loaded; install RSAT or import ActiveDirectory."
    }
}

function Test-IsDefaultGroupSid {
    # True when the SID looks like a well-known domain default group (Domain
    # Admins, Domain Users, etc.) — recursion through these can produce huge
    # member lists that drown out the meaningful permissions.
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Sid)
    if ([string]::IsNullOrWhiteSpace($Sid)) { return $false }
    if ($Sid -notmatch '^S-1-5-21-.*-(?<rid>\d+)$') { return $false }
    $rid = [int]$matches['rid']
    # Domain Admins / Users / Guests / Computers / Domain Controllers /
    # Cert Publishers / Schema Admins / Enterprise Admins / GPC Owners /
    # RODC / Cloneable DCs / Protected Users.
    return $rid -in 512,513,514,515,516,517,518,519,520,521,522,525
}

function Resolve-AdPrincipal {
    # Return ONE record describing the principal — Type, Domain, SAM, DN, error
    # cause if any. Group expansion is delegated to Expand-AdGroupMember; this
    # function never recurses, so callers get a stable shape for the direct
    # ACE/group-member entry.
    #
    # -CredentialMap is an optional FQDN(upper)→PSCredential hashtable. When the
    # principal's home domain is present in the map, the AD calls run as that
    # credential — letting the caller reach untrusted forests, or use a different
    # account than the jumphost's Kerberos context. Domains not in the map use
    # current Kerberos as before.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string]$Account,
        [Parameter(Mandatory)][hashtable]$DomainCache,
        [hashtable]$CredentialMap = @{}
    )

    # Built-in / well-known SIDs short-circuit (no AD lookup possible / needed).
    if ($Sid -match '^S-1-5-(18|19|20|32-)') {
        return [pscustomobject]@{
            Sid = $Sid; Account = $Account; Type = 'WellKnown'
            Domain = $null; SamAccountName = $null
            DistinguishedName = $null; ResolveError = $null
        }
    }

    $netbios = ($Account -split '\\', 2)[0]
    $fqdn    = Resolve-DomainFqdn -NetbiosName $netbios -Cache $DomainCache

    # No domain mapping for this netbios → it is the local SAM (computer name
    # or BUILTIN-style prefix that did not match the well-known regex above).
    # Local SAM SIDs always have the S-1-5-21-<machine>-<rid> shape.
    if (-not $fqdn) {
        $sam = if ($Account -like '*\*') { ($Account -split '\\', 2)[1] } else { $Account }
        $type = if ($Sid -match '^S-1-5-21-') { 'LocalAccount' } else { 'Unresolved' }
        return [pscustomobject]@{
            Sid = $Sid; Account = $Account; Type = $type
            Domain = $null; SamAccountName = $sam
            DistinguishedName = $null
            ResolveError = if ($type -eq 'Unresolved') { "No domain mapping for netbios '$netbios'" } else { $null }
        }
    }

    # Get-ADObject -Identity does not reliably accept a raw SID string —
    # the binder tries SAM/GUID/DN first and reports "Cannot find an object
    # with identity: 'S-1-5-…'". Query by objectSID filter (canonical), and
    # if that path errors (different AD module versions complain about
    # different filter syntax), fall back to passing a SecurityIdentifier
    # object to -Identity. -Properties does NOT expose 'SID' on Get-ADObject;
    # only ObjectSID. The SID we already have, so we don't ask for it back.
    $props = 'ObjectClass','SamAccountName','DistinguishedName'
    $obj   = $null
    $errFilter = $null

    $credKey = $fqdn.ToUpperInvariant()
    $adArgs  = @{ Server = $fqdn; Properties = $props; ErrorAction = 'Stop' }
    if ($CredentialMap -and $CredentialMap.ContainsKey($credKey)) {
        $adArgs['Credential'] = $CredentialMap[$credKey]
    }

    try {
        $obj = Get-ADObject -Filter "objectSID -eq '$Sid'" @adArgs |
            Select-Object -First 1
    } catch { $errFilter = $_.Exception.Message }

    if (-not $obj) {
        try {
            $sidObj = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $obj = Get-ADObject -Identity $sidObj @adArgs
        } catch { }
    }

    if (-not $obj) {
        $msg = if ($errFilter) { $errFilter } else { "No AD object with SID $Sid in $fqdn" }
        return [pscustomobject]@{
            Sid = $Sid; Account = $Account; Type = 'Unresolved'
            Domain = $fqdn; SamAccountName = $null
            DistinguishedName = $null
            ResolveError = $msg
        }
    }

    $type = switch ($obj.ObjectClass) {
        'user'                            { if ($Account.EndsWith('$')) { 'gMSA' } else { 'User' } }
        'msDS-GroupManagedServiceAccount' { 'gMSA' }
        'computer'                        { 'Computer' }
        'group'                           { 'Group' }
        default                           { 'User' }
    }

    [pscustomobject]@{
        Sid = $Sid; Account = $Account; Type = $type
        Domain = $fqdn; SamAccountName = $obj.SamAccountName
        DistinguishedName = $obj.DistinguishedName
        ResolveError = $null
    }
}
