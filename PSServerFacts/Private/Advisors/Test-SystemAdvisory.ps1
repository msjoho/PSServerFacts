function Test-SystemAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['System']) { return @() }
    $sys = $Result.System
    if ($null -eq $sys -or $null -eq $sys.LastHotfix -or $null -eq $sys.LastHotfix.InstalledOn) { return @() }
    $age = (New-TimeSpan -Start ([datetime]$sys.LastHotfix.InstalledOn) -End (Get-Date)).Days
    if ($age -le 60) { return @() }
    $sev = if ($age -gt 90) { 'Warning' } else { 'Note' }
    [pscustomobject]@{
        Section='System'; Severity=$sev; Rule='LastHotfixAge'
        Message="Last hotfix ($($sys.LastHotfix.HotFixID)) was installed $age days ago."
        Context=@{ HotFixID=$sys.LastHotfix.HotFixID; AgeDays=$age }
    }
}
