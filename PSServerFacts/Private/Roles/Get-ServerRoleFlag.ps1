function Get-ServerRoleFlag {
    # Derive boolean role flags from a server's collected result. Passed into
    # every advisor so they don't have to repeat role-detection logic. Defensive
    # against missing sections — the user may have run with -IncludeSection.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][object]$Result)

    $sqlProp    = $Result.PSObject.Properties['SqlServer']
    $sharesProp = $Result.PSObject.Properties['Shares']
    $iisProp    = $Result.PSObject.Properties['Iis']
    $chefProp   = $Result.PSObject.Properties['Chef']
    $featProp   = $Result.PSObject.Properties['WindowsFeatures']
    $svcProp    = $Result.PSObject.Properties['Services']

    $features = @(
        if ($null -ne $featProp) {
            $featProp.Value | Where-Object { $_.Installed } | ForEach-Object { $_.Name }
        }
    )
    $services = @(
        if ($null -ne $svcProp) {
            $svcProp.Value | ForEach-Object { $_.Name }
        }
    )

    $iisHasHttps = $false
    if (($null -ne $iisProp) -and ($null -ne $iisProp.Value)) {
        $iisHasHttps = [bool](@(
            $iisProp.Value.Sites |
                ForEach-Object { @($_.Bindings) } |
                Where-Object { $_.Protocol -eq 'https' }
        ).Count -gt 0)
    }

    $flags = [pscustomobject]@{
        HasSqlServer    = ($null -ne $sqlProp)    -and @($sqlProp.Value    | Where-Object { $null -ne $_ }).Count -gt 0
        HasIis          = ($null -ne $iisProp)    -and ($null -ne $iisProp.Value)
        HasFileShares   = ($null -ne $sharesProp) -and @($sharesProp.Value | Where-Object { $null -ne $_ }).Count -gt 0
        IsHyperVHost    = ('Hyper-V'            -in $features) -or ('vmms' -in $services)
        IsDc            = ('AD-Domain-Services' -in $features) -or ('NTDS' -in $services)
        IsChefManaged   = ($null -ne $chefProp) -and ($null -ne $chefProp.Value) -and [bool]$chefProp.Value.Installed
        IsCriticalRole  = $false
    }
    $flags.IsCriticalRole = $flags.HasSqlServer -or $flags.IsDc -or $flags.IsHyperVHost -or `
                            ($flags.HasIis -and $iisHasHttps)
    $flags
}
