function Get-RemoteCertificate {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [bool]$IncludeAllStores = $false
    )

    Invoke-Command -Session $Session -ArgumentList $IncludeAllStores -ScriptBlock {
        param($includeAll)

        $defaultStores = 'My','WebHosting','TrustedPublisher','Root','CA'
        $allStores     = (Get-ChildItem Cert:\LocalMachine -ErrorAction SilentlyContinue).PSChildName
        $stores        = if ($includeAll) { $allStores } else { $defaultStores }

        $now = Get-Date

        foreach ($store in $stores) {
            $path = "Cert:\LocalMachine\$store"
            if (-not (Test-Path $path)) { continue }
            Get-ChildItem $path -ErrorAction SilentlyContinue | ForEach-Object {
                $cert = $_
                $san  = @()
                $eku  = @()
                foreach ($ext in $cert.Extensions) {
                    switch ($ext.Oid.Value) {
                        '2.5.29.17' {
                            # SAN extraction. X509SubjectAlternativeNameExtension is .NET 5+ only;
                            # Windows PowerShell 5.1 (.NET Framework 4.x) on the remote target lacks it.
                            # Use the modern type if available, otherwise parse Format() output.
                            try {
                                $sanType = [System.Security.Cryptography.X509Certificates.X509SubjectAlternativeNameExtension] -as [type]
                                if ($sanType) {
                                    $sanExt = $sanType::new()
                                    $sanExt.CopyFrom($ext)
                                    $san = @($sanExt.EnumerateDnsNames())
                                } else {
                                    # Locale-tolerant: any "...DNS...=value" line. Handles English
                                    # ("DNS Name=foo"), German ("DNS-Name=foo"), and other variants.
                                    $san = @($ext.Format($true) -split "[\r\n]+" | ForEach-Object {
                                        $line = $_.Trim()
                                        if ($line -match '^(?:[^=]*DNS[^=]*)=(.+)$') { $matches[1].Trim() }
                                    } | Where-Object { $_ })
                                }
                            } catch {
                                $san = @()
                            }
                        }
                        '2.5.29.37' {
                            try {
                                $eku = @(([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$ext).EnhancedKeyUsages | ForEach-Object FriendlyName)
                            } catch {
                                $eku = @()
                            }
                        }
                    }
                }
                [pscustomobject]@{
                    Store           = "LocalMachine\$store"
                    Subject         = $cert.Subject
                    Issuer          = $cert.Issuer
                    Thumbprint      = $cert.Thumbprint
                    SerialNumber    = $cert.SerialNumber
                    NotBeforeUtc    = $cert.NotBefore.ToUniversalTime().ToString('o')
                    NotAfterUtc     = $cert.NotAfter.ToUniversalTime().ToString('o')
                    DaysUntilExpiry = [int]([math]::Floor(($cert.NotAfter - $now).TotalDays))
                    Expired         = ($cert.NotAfter -lt $now)
                    HasPrivateKey   = $cert.HasPrivateKey
                    FriendlyName    = $cert.FriendlyName
                    SubjectAlternativeNames = @($san)
                    EnhancedKeyUsage        = @($eku)
                }
            }
        }
    } | Select-Object Store, Subject, Issuer, Thumbprint, SerialNumber, NotBeforeUtc, NotAfterUtc, DaysUntilExpiry, Expired, HasPrivateKey, FriendlyName, SubjectAlternativeNames, EnhancedKeyUsage
}
