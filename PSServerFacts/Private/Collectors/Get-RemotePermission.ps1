function Get-RemotePermission {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        function Get-RawMembers([string]$GroupName) {
            # Get-LocalGroupMember is the clean source of SID + account, but it
            # throws "Failed to compare two elements in the array" on Server
            # 2016/2019 the moment the group contains an unresolvable AD SID
            # (deleted account, broken trust). The ADSI WinNT provider survives
            # those entries and gives us at least the path + objectSid bytes,
            # so use it as a fallback when Get-LocalGroupMember errors.
            try {
                $rows = Get-LocalGroupMember -Group $GroupName -ErrorAction Stop |
                    ForEach-Object { [pscustomobject]@{ Sid = $_.SID.Value; Account = $_.Name } }
                return @($rows)
            } catch { }
            try {
                $grp = [ADSI]("WinNT://./" + $GroupName + ",group")
                $members = $grp.psbase.Invoke('Members')
                $rows = foreach ($m in $members) {
                    $path = try { $m.GetType().InvokeMember('AdsPath','GetProperty',$null,$m,$null) } catch { $null }
                    $name = try { $m.GetType().InvokeMember('Name','GetProperty',$null,$m,$null)    } catch { $null }
                    # WinNT://DOMAIN/User  ->  DOMAIN\User
                    # WinNT://./User       ->  <Computer>\User
                    $account = if ($path -match '^WinNT://([^/]+)/([^/]+)$') { "$($matches[1])\$($matches[2])" } else { $name }

                    $sid = $null
                    # Preferred: ask LSA to translate the resolved name. Works for
                    # any local/domain user or group still resolvable from this host.
                    if ($account) {
                        try {
                            $sid = (New-Object System.Security.Principal.NTAccount($account)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                        } catch { }
                    }
                    # Fallback: pull the raw objectSid bytes from ADSI. Survives
                    # orphaned/cross-trust members where LSA translation fails.
                    if (-not $sid) {
                        try {
                            $raw = $m.GetType().InvokeMember('objectSid','GetProperty',$null,$m,$null)
                            if ($raw) {
                                $byteArr = [byte[]]@($raw | ForEach-Object { [byte]$_ })
                                $sid = (New-Object System.Security.Principal.SecurityIdentifier($byteArr, 0)).Value
                            }
                        } catch { }
                    }
                    if ([string]::IsNullOrWhiteSpace($account) -and [string]::IsNullOrWhiteSpace($sid)) { continue }
                    [pscustomobject]@{ Sid = $sid; Account = $account }
                }
                return @($rows)
            } catch { }
            return @()
        }
        [pscustomobject]@{
            Administrators        = @(Get-RawMembers 'Administrators')
            RemoteDesktopUsers    = @(Get-RawMembers 'Remote Desktop Users')
            RemoteManagementUsers = @(Get-RawMembers 'Remote Management Users')
        }
    } | Select-Object Administrators, RemoteDesktopUsers, RemoteManagementUsers
}
