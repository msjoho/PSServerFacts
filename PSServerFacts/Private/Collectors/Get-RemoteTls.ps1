function Get-RemoteTls {
    # Walks HKLM\SYSTEM\…\SCHANNEL\Protocols\<protocol>\<side>\. Missing key →
    # OS default for that protocol (defaults differ by Windows version; we
    # encode the most common Server 2016/2019/2022 baseline below).
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
        # SSL 2/3 disabled by default since Server 2016; TLS 1.0/1.1 enabled-
        # but-deprecated on 2016/2019, disabled by default on 2022+.
        $defaults = @{
            'SSL 2.0' = @{ Enabled = $false; DisabledByDefault = $true  }
            'SSL 3.0' = @{ Enabled = $false; DisabledByDefault = $true  }
            'TLS 1.0' = @{ Enabled = $true;  DisabledByDefault = $false }
            'TLS 1.1' = @{ Enabled = $true;  DisabledByDefault = $false }
            'TLS 1.2' = @{ Enabled = $true;  DisabledByDefault = $false }
            'TLS 1.3' = @{ Enabled = $true;  DisabledByDefault = $false }
        }
        $rows = foreach ($name in 'SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1','TLS 1.2','TLS 1.3') {
            foreach ($side in 'Client','Server') {
                $keyPath = Join-Path $base "$name\$side"
                $enabled = $defaults[$name].Enabled
                $disbyd  = $defaults[$name].DisabledByDefault
                if (Test-Path $keyPath) {
                    try {
                        $reg = Get-ItemProperty $keyPath -ErrorAction Stop
                        if ($reg.PSObject.Properties['Enabled']) {
                            $enabled = [int]$reg.Enabled -ne 0
                        }
                        if ($reg.PSObject.Properties['DisabledByDefault']) {
                            $disbyd = [int]$reg.DisabledByDefault -ne 0
                        }
                    } catch { }
                }
                [pscustomobject]@{
                    Name              = $name
                    Side              = $side
                    Enabled           = $enabled
                    DisabledByDefault = $disbyd
                }
            }
        }
        [pscustomobject]@{ Protocols = @($rows) }
    }
}
