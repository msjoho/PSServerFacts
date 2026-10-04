function Test-PowerPlanAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['PowerPlan']) { return @() }
    $pp = $Result.PowerPlan
    if ($null -eq $pp) { return @() }
    # High Performance scheme GUID (invariant across Windows builds).
    $HIGH_PERF = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    if ($pp.ActiveSchemeGuid -eq $HIGH_PERF) { return @() }

    $sev = if ($Roles.IsCriticalRole) { 'Warning' } else { 'Note' }
    [pscustomobject]@{
        Section  = 'PowerPlan'
        Severity = $sev
        Rule     = 'PowerPlanNotHighPerf'
        Message  = "Active power plan is '$($pp.ActiveSchemeName)'. SQL/critical workloads should use High Performance to avoid CPU throttling."
        Context  = @{ ActivePlan = $pp.ActiveSchemeName; Recommended = 'High Performance' }
    }
}
