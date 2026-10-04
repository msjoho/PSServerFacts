function Test-PageFileAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['PageFile']) { return @() }
    $pf = $Result.PageFile
    if ($null -eq $pf -or -not $pf.AutomaticManagedPagefile) { return @() }

    $sev = if ($Roles.HasSqlServer) { 'Warning' } else { 'Note' }
    [pscustomobject]@{
        Section  = 'PageFile'
        Severity = $sev
        Rule     = 'PageFileAutoManaged'
        Message  = 'Page file is system-managed. SQL/critical hosts should use a fixed Initial=Max page file (predictable, no growth fragmentation).'
        Context  = @{ AutomaticManagedPagefile = $true }
    }
}
