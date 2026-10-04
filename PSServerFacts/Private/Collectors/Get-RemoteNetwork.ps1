function Get-RemoteNetwork {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $cs   = Get-CimInstance Win32_ComputerSystem
        $fqdn = "$($cs.DNSHostName).$($cs.Domain)"

        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -ne 'Disabled' -and $_.InterfaceDescription -notmatch 'isatap|Teredo|Loopback' }

        $list = foreach ($a in $adapters) {
            $cfg = Get-NetIPConfiguration -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue
            $ip4 = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                ForEach-Object { [pscustomobject]@{ Address=$_.IPAddress; PrefixLength=$_.PrefixLength } }
            $ip6 = Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
                Where-Object { $_.PrefixOrigin -ne 'WellKnown' } |
                ForEach-Object { [pscustomobject]@{ Address=$_.IPAddress; PrefixLength=$_.PrefixLength } }
            $dns = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses

            [pscustomobject]@{
                Name=$a.Name; Description=$a.InterfaceDescription
                MacAddress=$a.MacAddress; Status=$a.Status
                DhcpEnabled = ($cfg.NetIPv4Interface.Dhcp -eq 'Enabled')
                IPv4 = @($ip4)
                IPv6 = @($ip6)
                DefaultGateway = ($cfg.IPv4DefaultGateway.NextHop | Select-Object -First 1)
                DnsServers = @($dns)
                DnsSuffix = (Get-DnsClient -InterfaceIndex $a.ifIndex -ErrorAction SilentlyContinue).ConnectionSpecificSuffix
            }
        }

        [pscustomobject]@{ Hostname=$cs.DNSHostName; Fqdn=$fqdn; Adapters=@($list) }
    } | Select-Object Hostname, Fqdn, Adapters
}
