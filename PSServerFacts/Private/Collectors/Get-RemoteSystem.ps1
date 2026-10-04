function Get-RemoteSystem {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $os  = Get-CimInstance Win32_OperatingSystem
        $cs  = Get-CimInstance Win32_ComputerSystem
        $hf  = Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 1

        $winRmCert = $null
        try {
            $listener = Get-ChildItem WSMan:\localhost\Listener -ErrorAction Stop |
                Where-Object { (Get-Item "$($_.PSPath)\Transport").Value -eq 'HTTPS' } | Select-Object -First 1
            if ($listener) {
                $winRmCert = (Get-Item "$($listener.PSPath)\CertificateThumbprint" -ErrorAction Stop).Value
            }
        } catch {}

        [pscustomobject]@{
            OsCaption                = $os.Caption
            OsVersion                = $os.Version
            OsBuild                  = "$($os.BuildNumber).$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name UBR -ErrorAction SilentlyContinue).UBR)"
            InstallDateUtc           = $os.InstallDate.ToUniversalTime().ToString('o')
            LastBootUtc              = $os.LastBootUpTime.ToUniversalTime().ToString('o')
            LastHotfix               = if ($hf) { [pscustomobject]@{ HotFixId=$hf.HotFixID; InstalledOnUtc=([datetime]$hf.InstalledOn).ToUniversalTime().ToString('o') } } else { $null }
            Domain                   = $cs.Domain
            TimeZone                 = (Get-TimeZone).Id
            WinRmHttpsCertThumbprint = $winRmCert
        }
    } | Select-Object OsCaption, OsVersion, OsBuild, InstallDateUtc, LastBootUtc, LastHotfix, Domain, TimeZone, WinRmHttpsCertThumbprint
}
