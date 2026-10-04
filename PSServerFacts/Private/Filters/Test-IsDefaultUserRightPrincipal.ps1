function Test-IsDefaultUserRightPrincipal {
    # True when this principal account is in the per-privilege defaults list.
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Privilege,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Account,
        [Parameter(Mandatory)][hashtable]$Defaults
    )
    if (-not $Defaults.ContainsKey($Privilege)) { return $false }
    $list = @($Defaults[$Privilege])
    foreach ($d in $list) {
        if ([string]::Equals($d, $Account, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
