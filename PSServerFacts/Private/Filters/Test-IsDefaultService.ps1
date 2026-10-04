function Test-IsDefaultService {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][object]$Service,                  # has Name, PathName
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KnownDefaults,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$KnownCustomFalsePositives
    )

    if ($KnownCustomFalsePositives -contains $Service.Name) { return $false }
    if ($KnownDefaults              -contains $Service.Name) { return $true }

    $raw = [string]$Service.PathName
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }

    # Strip surrounding quotes; take token up to first whitespace if not quoted.
    if ($raw -match '^\s*"([^"]+)"') {
        $bin = $matches[1]
    } else {
        $bin = ($raw.Trim() -split '\s+', 2)[0]
    }
    $bin = [Environment]::ExpandEnvironmentVariables($bin)

    $sysRoot   = [Environment]::ExpandEnvironmentVariables('%SystemRoot%').TrimEnd('\')
    $system32  = "$sysRoot\System32\"
    $sysWow64  = "$sysRoot\SysWOW64\"
    $sysOther  = "$sysRoot\"

    $lower = $bin.ToLowerInvariant()
    foreach ($prefix in @($system32, $sysWow64, $sysOther)) {
        if ($lower.StartsWith($prefix.ToLowerInvariant())) { return $true }
    }
    return $false
}
