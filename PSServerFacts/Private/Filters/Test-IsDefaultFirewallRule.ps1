function Test-IsDefaultFirewallRule {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Group,
        [Parameter(Mandatory)][string[]]$GroupPrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Group)) { return $false }
    foreach ($prefix in $GroupPrefixes) {
        if ($Group.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
