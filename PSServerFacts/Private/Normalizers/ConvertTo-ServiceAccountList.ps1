function ConvertTo-ServiceAccountList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Services,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ScheduledTasks,
        [AllowNull()][object]$Iis,
        [Parameter(Mandatory)][string]$Hostname
    )

    function Test-IsDomainAccount {
        param([string]$Account, [string]$Hostname)
        if ([string]::IsNullOrWhiteSpace($Account)) { return $false }
        $excludePrefixes = @(
            'NT AUTHORITY\','BUILTIN\','NT SERVICE\','APPLICATION PACKAGE AUTHORITY\',
            "$Hostname\".ToUpperInvariant()
        )
        $upper = $Account.ToUpperInvariant()
        foreach ($p in $excludePrefixes) { if ($upper.StartsWith($p.ToUpperInvariant())) { return $false } }
        $excludeNames = @('LOCALSYSTEM','LOCALSERVICE','NETWORKSERVICE','SYSTEM')
        if ($excludeNames -contains $upper) { return $false }
        if ($Account -match '^[^\\]+\\[^\\]+$' -or $Account -match '^[^@]+@[^@]+$') { return $true }
        return $false
    }

    $map = [ordered]@{}

    foreach ($s in $Services) {
        $a = [string]$s.StartName
        if (Test-IsDomainAccount -Account $a -Hostname $Hostname) {
            if (-not $map.Contains($a)) {
                $map[$a] = [pscustomobject]@{
                    Account = $a
                    Type    = $(if ($a.EndsWith('$')) { 'gMSA' } else { 'User' })
                    UsedBy  = [System.Collections.Generic.List[object]]::new()
                }
            }
            $map[$a].UsedBy.Add([pscustomobject]@{ Kind='Service'; Name=$s.Name })
        }
    }
    foreach ($t in $ScheduledTasks) {
        $a = [string]$t.RunAs
        if (Test-IsDomainAccount -Account $a -Hostname $Hostname) {
            if (-not $map.Contains($a)) {
                $map[$a] = [pscustomobject]@{
                    Account = $a
                    Type    = $(if ($a.EndsWith('$')) { 'gMSA' } else { 'User' })
                    UsedBy  = [System.Collections.Generic.List[object]]::new()
                }
            }
            $map[$a].UsedBy.Add([pscustomobject]@{ Kind='ScheduledTask'; Path="$($t.TaskPath)$($t.TaskName)" })
        }
    }
    if ($Iis -and $Iis.Installed -and $Iis.AppPools) {
        foreach ($pool in $Iis.AppPools) {
            $a = [string]$pool.Username
            if (Test-IsDomainAccount -Account $a -Hostname $Hostname) {
                if (-not $map.Contains($a)) {
                    $map[$a] = [pscustomobject]@{
                        Account = $a
                        Type    = $(if ($a.EndsWith('$')) { 'gMSA' } else { 'User' })
                        UsedBy  = [System.Collections.Generic.List[object]]::new()
                    }
                }
                $map[$a].UsedBy.Add([pscustomobject]@{ Kind='IISAppPool'; Name=$pool.Name })
            }
        }
    }

    return @($map.Values)
}
