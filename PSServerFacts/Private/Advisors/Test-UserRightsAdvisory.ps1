function Test-UserRightsAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['UserRightsAssignment']) { return @() }
    $ura = @($Result.UserRightsAssignment)
    if ($ura.Count -eq 0) { return @() }

    # SeTcbPrivilege ("act as part of the operating system") on any non-Admins principal is Critical.
    $tcb = $ura | Where-Object Privilege -eq 'SeTcbPrivilege' | Select-Object -First 1
    if (-not $tcb) { return @() }
    $nonAdmin = @($tcb.Principals | Where-Object { $_.Sid -ne 'S-1-5-32-544' })
    if ($nonAdmin.Count -eq 0) { return @() }
    [pscustomobject]@{
        Section='UserRightsAssignment'; Severity='Critical'; Rule='TcbPrivilegeOnNonAdmin'
        Message="Non-Administrator principals have SeTcbPrivilege: $(@($nonAdmin | ForEach-Object Account) -join ', '). This privilege bypasses ACLs."
        Context=@{ Principals = @($nonAdmin | ForEach-Object Account) }
    }
}
