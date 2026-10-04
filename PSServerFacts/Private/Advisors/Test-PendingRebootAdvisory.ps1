function Test-PendingRebootAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['PendingReboot']) { return @() }
    $pr = $Result.PendingReboot
    if ($null -eq $pr -or -not $pr.Any) { return @() }

    $sources = New-Object System.Collections.Generic.List[string]
    if ($pr.ComponentBasedServicing) { $sources.Add('Component Based Servicing') | Out-Null }
    if ($pr.WindowsUpdate)           { $sources.Add('Windows Update')             | Out-Null }
    if ($pr.PendingFileRenameOps)    { $sources.Add('pending file rename ops')    | Out-Null }
    if ($pr.ComputerNameChange)      { $sources.Add('computer-name change')       | Out-Null }
    if ($pr.CcmClientSDK)            { $sources.Add('SCCM/CCM client')            | Out-Null }

    [pscustomobject]@{
        Section  = 'PendingReboot'
        Severity = 'Note'
        Rule     = 'PendingRebootFlag'
        Message  = "Server has a pending reboot ($(($sources -join ', ')))."
        Context  = @{ Sources = @($sources) }
    }
}
