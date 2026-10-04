function Test-IsDefaultCertIssuer {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Issuer,
        [Parameter(Mandatory)][string[]]$DefaultIssuers
    )
    foreach ($needle in $DefaultIssuers) {
        if ($Issuer -like "*$needle*") { return $true }
    }
    return $false
}
