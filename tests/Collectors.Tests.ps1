. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteService' {
    BeforeAll {
        # We need a real [PSSession] instance to satisfy the strict parameter
        # type on Get-RemoteService. The mocked Invoke-Command never actually
        # uses it, but Pester's mock proxy still binds parameters against the
        # real Invoke-Command signature. UseWindowsPowerShell sessions don't
        # require WinRM and are cheap to create locally.
        $script:Session = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:Session) { Remove-PSSession $script:Session }
    }
    It 'returns full Win32_Service projection' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            ,@([pscustomobject]@{
                Name='X'; DisplayName='X svc'; State='Running'; StartMode='Auto'
                PathName='"D:\App\x.exe"'; StartName='CORP\msvc'; Description='d'
            })
        }
        (Get-RemoteService -Session $script:Session).Count | Should -Be 1
    }

    It 'propagates remote terminating errors' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command { throw 'remote WMI failed' }
        { Get-RemoteService -Session $script:Session } | Should -Throw -ExpectedMessage '*remote WMI failed*'
    }

    It 'returns an empty array when no services exist on the remote' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command { }
        $r = @(Get-RemoteService -Session $script:Session)
        $r.Count | Should -Be 0
    }
}

Describe 'Get-RemoteSystem' {
    BeforeAll {
        $script:Session = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:Session) { Remove-PSSession -Session $script:Session -ErrorAction SilentlyContinue }
    }
    It 'returns the System shape' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                OsCaption = 'Microsoft Windows Server 2019 Standard'
                OsVersion = '10.0.17763'
                OsBuild   = '17763.5458'
                InstallDateUtc = '2021-03-12T08:14:00Z'
                LastBootUtc    = '2026-04-22T03:11:00Z'
                LastHotfix     = [pscustomobject]@{ HotFixId='KB5037765'; InstalledOnUtc='2026-04-12T00:00:00Z' }
                Domain         = 'corp.contoso.com'
                TimeZone       = 'W. Europe Standard Time'
                WinRmHttpsCertThumbprint = $null
            }
        }
        $r = Get-RemoteSystem -Session $script:Session
        $r.OsCaption | Should -Match 'Server 2019'
        $r.Domain    | Should -Be 'corp.contoso.com'
    }
}

Describe 'Get-RemoteHardware' {
    BeforeAll {
        $script:HwSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:HwSession) { Remove-PSSession -Session $script:HwSession -ErrorAction SilentlyContinue }
    }
    It 'returns the Hardware shape' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{ CpuModel='Xeon'; CpuSockets=2; CpuLogicalCores=16; MemoryTotalGB=64.0 }
        }
        $r = Get-RemoteHardware -Session $script:HwSession
        $r.MemoryTotalGB | Should -Be 64.0
        $r.CpuSockets    | Should -Be 2
    }
}

Describe 'Get-RemoteDisks' {
    BeforeAll {
        $script:DiskSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:DiskSession) { Remove-PSSession -Session $script:DiskSession -ErrorAction SilentlyContinue }
    }
    It 'returns array of fixed-disk records' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{ Drive='C:'; Label='OS';   FileSystem='NTFS'; TotalGB=100.0; FreeGB=32.0; UsedPct=68.0 }
                [pscustomobject]@{ Drive='D:'; Label='Data'; FileSystem='NTFS'; TotalGB=500.0; FreeGB=125.0; UsedPct=75.0 }
            )
        }
        $r = @(Get-RemoteDisks -Session $script:DiskSession)
        $r.Count | Should -Be 2
    }
}

Describe 'Get-RemoteNetwork' {
    BeforeAll {
        $script:NetSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:NetSession) { Remove-PSSession -Session $script:NetSession -ErrorAction SilentlyContinue }
    }
    It 'returns the Network shape with adapters' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Hostname='SRV1'
                Fqdn='SRV1.corp.contoso.com'
                Adapters = @(
                    [pscustomobject]@{
                        Name='Ethernet0'; Description='X'; MacAddress='00:11:22:33:44:55'; Status='Up'
                        DhcpEnabled=$false
                        IPv4=@([pscustomobject]@{ Address='10.0.0.5'; PrefixLength=24 })
                        IPv6=@(); DefaultGateway='10.0.0.1'
                        DnsServers=@('10.0.0.10','10.0.0.11'); DnsSuffix='corp.contoso.com'
                    }
                )
            }
        }
        $r = Get-RemoteNetwork -Session $script:NetSession
        $r.Adapters.Count | Should -Be 1
        $r.Adapters[0].IPv4[0].Address | Should -Be '10.0.0.5'
    }
}

Describe 'Get-RemoteInstalledApplication' {
    BeforeAll {
        $script:AppSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:AppSession) { Remove-PSSession -Session $script:AppSession -ErrorAction SilentlyContinue }
    }
    It 'returns DisplayName-bearing entries' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{ DisplayName='App'; Version='1.0'; Publisher='Acme'; InstallDateUtc=$null; InstallLocation='C:\App'; Source='Registry'; UninstallString='msiexec /x' }
            )
        }
        $r = @(Get-RemoteInstalledApplication -Session $script:AppSession)
        $r.Count | Should -Be 1
        $r[0].DisplayName | Should -Be 'App'
    }
}

Describe 'Get-RemoteChocolateyPackage' {
    BeforeAll {
        $script:ChocoSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:ChocoSession) { Remove-PSSession -Session $script:ChocoSession -ErrorAction SilentlyContinue }
    }
    It 'returns empty array when choco missing' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command { @() }
        $r = @(Get-RemoteChocolateyPackage -Session $script:ChocoSession)
        $r.Count | Should -Be 0
    }
    It 'returns parsed packages when present' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{ Id='git';    Version='2.44.0' }
                [pscustomobject]@{ Id='nodejs'; Version='20.10.0' }
            )
        }
        $r = @(Get-RemoteChocolateyPackage -Session $script:ChocoSession)
        $r.Count | Should -Be 2
        $r[0].Id | Should -Be 'git'
    }
}

Describe 'Get-RemoteWindowsFeature' {
    BeforeAll {
        $script:FeatSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:FeatSession) { Remove-PSSession -Session $script:FeatSession -ErrorAction SilentlyContinue }
    }
    It 'returns feature list on Server SKU' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @([pscustomobject]@{ Name='Web-Server'; DisplayName='Web Server (IIS)' })
        }
        $r = @(Get-RemoteWindowsFeature -Session $script:FeatSession)
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'Web-Server'
    }
}

Describe 'Get-RemotePermission' {
    BeforeAll {
        $script:PermSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:PermSession) { Remove-PSSession -Session $script:PermSession -ErrorAction SilentlyContinue }
    }
    It 'returns raw entries for the three groups' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Administrators        = @([pscustomobject]@{ Sid='S-1-5-21-1'; Account='CORP\jdoe' })
                RemoteDesktopUsers    = @()
                RemoteManagementUsers = @()
            }
        }
        $r = Get-RemotePermission -Session $script:PermSession
        $r.Administrators.Count | Should -Be 1
        $r.Administrators[0].Account | Should -Be 'CORP\jdoe'
        $r.RemoteDesktopUsers.Count | Should -Be 0
    }
}

Describe 'Get-RemoteShare' {
    BeforeAll {
        $script:ShareSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:ShareSession) { Remove-PSSession -Session $script:ShareSession -ErrorAction SilentlyContinue }
    }
    It 'returns raw shares with permissions' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{
                    Name='Finance'; Path='D:\Shares\Finance'; Description='F'
                    SharePermissions = @([pscustomobject]@{ Account='CORP\Finance-RW'; AccessRight='Change'; AccessControlType='Allow' })
                    NtfsRawAces      = @([pscustomobject]@{ IdentityReference='CORP\Finance-RW'; FileSystemRights='Modify'; AccessControlType='Allow'; IsInherited=$false; InheritanceFlags='ContainerInherit, ObjectInherit'; PropagationFlags='None' })
                    NtfsSourceKind   = 'GetAcl'
                    NtfsErrors       = @()
                }
            )
        }
        $r = @(Get-RemoteShare -Session $script:ShareSession -NtfsDepth 'Root' -NtfsSecurityProvisioning 'None')
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'Finance'
    }
    It 'passes NtfsDepth and NtfsSecurityProvisioning to remote scriptblock' {
        $script:capturedArgs = $null
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            $script:capturedArgs = $ArgumentList
            @()
        }
        Get-RemoteShare -Session $script:ShareSession -NtfsDepth 'Children' -NtfsSecurityProvisioning 'Install' | Out-Null
        $script:capturedArgs[0] | Should -Be 'Children'
        $script:capturedArgs[1] | Should -Be 'Install'
    }
}

Describe 'Get-RemoteScheduledTask' {
    BeforeAll {
        $script:TaskSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:TaskSession) { Remove-PSSession -Session $script:TaskSession -ErrorAction SilentlyContinue }
    }
    It 'returns task records with raw triggers' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{
                    TaskPath='\Backups\'; TaskName='Nightly'; State='Ready'; RunAs='CORP\msvc_backup'
                    Triggers=@([pscustomobject]@{ CimClass=@{ CimClassName='MSFT_TaskDailyTrigger' }; StartBoundary='2026-04-30T02:00:00'; DaysInterval=1 })
                    Actions=@([pscustomobject]@{ Execute='powershell.exe'; Arguments='-File X' })
                }
            )
        }
        $r = @(Get-RemoteScheduledTask -Session $script:TaskSession)
        $r.Count | Should -Be 1
        $r[0].TaskName | Should -Be 'Nightly'
        $r[0].Triggers.Count | Should -Be 1
        $r[0].Actions[0].Execute | Should -Be 'powershell.exe'
    }
}

Describe 'Get-RemoteLocalUser' {
    BeforeAll {
        $script:LuSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:LuSession) { Remove-PSSession -Session $script:LuSession -ErrorAction SilentlyContinue }
    }
    It 'returns non-default local users' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{
                    Name='svc_localmaint'; Enabled=$true
                    PasswordLastSetUtc='2025-11-02T08:00:00Z'; PasswordNeverExpires=$true
                    Description='maintenance'; Sid='S-1-5-21-1-2-3-1010'
                }
            )
        }
        $r = @(Get-RemoteLocalUser -Session $script:LuSession)
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'svc_localmaint'
    }
}

Describe 'Get-RemoteFirewallRule' {
    BeforeAll {
        $script:FwSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:FwSession) { Remove-PSSession -Session $script:FwSession -ErrorAction SilentlyContinue }
    }
    It 'returns raw rule records (filtering happens later)' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{
                    DisplayName='MyApp'; Direction='Inbound'; Action='Allow'
                    Profile='Domain'; Enabled=$true
                    LocalPort='8443'; Protocol='TCP'
                    Program='D:\App\x.exe'; RemoteAddress='Any'; Group=$null
                }
            )
        }
        $r = @(Get-RemoteFirewallRule -Session $script:FwSession)
        $r.Count | Should -Be 1
        $r[0].DisplayName | Should -Be 'MyApp'
    }
}

Describe 'Get-RemoteIis' {
    BeforeAll {
        $script:IisSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:IisSession) { Remove-PSSession -Session $script:IisSession -ErrorAction SilentlyContinue }
    }
    It 'returns null when IIS feature not installed' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command { $null }
        $r = Get-RemoteIis -Session $script:IisSession
        $r | Should -BeNullOrEmpty
    }
    It 'returns Iis shape when installed' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Installed=$true; Version='10.0.17763.1'
                Sites=@(); AppPools=@(); CollectionErrors=@()
            }
        }
        $r = Get-RemoteIis -Session $script:IisSession
        $r.Installed | Should -BeTrue
        $r.Version   | Should -Be '10.0.17763.1'
    }
}

Describe 'Get-RemoteCertificate' {
    BeforeAll {
        $script:CertSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:CertSession) { Remove-PSSession -Session $script:CertSession -ErrorAction SilentlyContinue }
    }
    It 'returns certs across the configured stores' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                [pscustomobject]@{
                    Store='LocalMachine\My'
                    Subject='CN=x'; Issuer='CN=Contoso CA'; Thumbprint='AB12'
                    SerialNumber='001'
                    NotBeforeUtc='2025-01-01T00:00:00Z'; NotAfterUtc='2027-01-01T00:00:00Z'
                    DaysUntilExpiry=300; Expired=$false; HasPrivateKey=$true
                    FriendlyName=$null; SubjectAlternativeNames=@(); EnhancedKeyUsage=@()
                }
            )
        }
        $r = @(Get-RemoteCertificate -Session $script:CertSession -IncludeAllStores:$false)
        $r.Count | Should -Be 1
        $r[0].Store | Should -Be 'LocalMachine\My'
        $r[0].Thumbprint | Should -Be 'AB12'
    }
}

