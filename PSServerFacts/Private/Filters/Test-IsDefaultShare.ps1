function Test-IsDefaultShare {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$DefaultNames
    )
    if ($Name -match '^[A-Za-z]\$$') { return $true }       # letter-drive admin shares
    return [bool]($DefaultNames -contains $Name -or $DefaultNames -contains $Name.ToUpperInvariant())
}
