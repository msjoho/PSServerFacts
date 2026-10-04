function Test-DefenderAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['Defender']) { return @() }
    $def = $Result.Defender
    if ($null -eq $def) { return @() }

    if ($def.Engine -and $def.Engine.RealTimeProtectionEnabled -eq $false) {
        [pscustomobject]@{
            Section='Defender'; Severity='Critical'; Rule='DefenderRtDisabled'
            Message='Microsoft Defender real-time protection is disabled.'
            Context=@{ Setting='RealTimeProtectionEnabled'; Recommended=$true }
        }
    }

    if (-not $Roles.HasSqlServer) { return @() }
    $excl = @()
    if ($def.Exclusions) {
        $excl = @($def.Exclusions.Paths) | Where-Object { $_ }
    }
    $sqlPaths = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($inst in @($Result.SqlServer)) {
        foreach ($db in @($inst.Databases)) {
            foreach ($f in @($db.Files)) {
                if ($f.Path) { [void]$sqlPaths.Add((Split-Path $f.Path -Parent)) }
            }
        }
    }
    $missing = foreach ($p in $sqlPaths) {
        $covered = $false
        foreach ($e in $excl) {
            if ($p -like "$e*" -or $p -ieq $e) { $covered = $true; break }
        }
        if (-not $covered) { $p }
    }
    if (@($missing).Count -gt 0) {
        [pscustomobject]@{
            Section='Defender'; Severity='Warning'; Rule='DefenderMissingSqlExclusion'
            Message="SQL data/log directories not covered by Defender exclusions: $(@($missing) -join ', '). Add to ExclusionPath to avoid scan latency hits on hot files."
            Context=@{ MissingPaths=@($missing); ExistingExclusions=@($excl) }
        }
    }
}
