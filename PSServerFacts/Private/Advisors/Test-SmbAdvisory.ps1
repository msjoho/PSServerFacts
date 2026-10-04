function Test-SmbAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['Smb']) { return @() }
    $smb = $Result.Smb
    if ($null -eq $smb) { return @() }

    if ($smb.Smb1Enabled -eq $true) {
        [pscustomobject]@{
            Section='Smb'; Severity='Critical'; Rule='Smb1Enabled'
            Message='SMB1 is enabled. EternalBlue/WannaCry vector — disable immediately.'
            Context=@{ Setting='EnableSMB1Protocol'; Recommended=$false }
        }
    }
    if ($smb.SigningRequired -eq $false) {
        [pscustomobject]@{
            Section='Smb'; Severity='Warning'; Rule='SmbSigningNotRequired'
            Message='SMB signing is not required. Enables relay attacks against this server.'
            Context=@{ Setting='RequireSecuritySignature'; Recommended=$true }
        }
    }
}
