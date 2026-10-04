. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-ServerFacts' {
    BeforeAll {
        $script:DomainCache = [hashtable]::Synchronized(@{ 'CORP' = 'corp.contoso.com' })
        $script:DataFiles = @{
            DefaultServices              = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultServices.psd1"
            DefaultShares                = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultShares.psd1"
            DefaultTaskPaths             = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultTaskPaths.psd1"
            DefaultCertIssuers           = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultCertIssuers.psd1"
            DefaultFirewallGroupPrefixes = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultFirewallGroupPrefixes.psd1"
            DefaultUserRights            = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultUserRights.psd1"
        }
        $script:AllSections = @('System','Hardware','Disks','Network','InstalledApplications',
            'ChocolateyPackages','WindowsFeatures','Permissions','Services','Shares',
            'ScheduledTasks','LocalUsers','FirewallRules','Iis','Certificates')
        # Real local PSSession satisfies the strict [PSSession] type on each collector;
        # the actual remoting never happens because collectors are mocked directly.
        $script:RealSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll {
        if ($script:RealSession) { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }
    }

    It 'returns a Failed stub when the session cannot be opened' {
        Mock -ModuleName 'PSServerFacts' New-PSSession { throw 'WinRM unreachable' }
        $r = Get-ServerFacts -ComputerName 'ghost' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -Section $script:AllSections
        $r.Computer          | Should -Be 'ghost'
        $r.Status            | Should -Be 'Failed'
        $r.Errors[0].Section | Should -Be 'Connect'
        @($r.CollectedSections).Count | Should -Be 0
    }

    It 'composes a Success result when all collectors succeed' {
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}

        Mock -ModuleName 'PSServerFacts' Get-RemoteSystem               { [pscustomobject]@{ OsCaption = 'Server 2019'; OsVersion = '10'; OsBuild = '1'; InstallDateUtc = $null; LastBootUtc = $null; LastHotfix = $null; Domain = 'corp.contoso.com'; TimeZone = 'UTC'; WinRmHttpsCertThumbprint = $null } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteHardware             { [pscustomobject]@{ CpuModel = 'Xeon'; CpuSockets = 2; CpuLogicalCores = 16; MemoryTotalGB = 64.0 } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteDisks                { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteNetwork              { [pscustomobject]@{ Hostname = 'srv1'; Fqdn = 'srv1.x'; Adapters = @() } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteInstalledApplication { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteChocolateyPackage    { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteWindowsFeature       { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemotePermission           { [pscustomobject]@{ Administrators = @(); RemoteDesktopUsers = @(); RemoteManagementUsers = @() } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteService              { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteShare                { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteScheduledTask        { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteLocalUser            { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteFirewallRule         { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteIis                  { $null }
        Mock -ModuleName 'PSServerFacts' Get-RemoteCertificate          { @() }

        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -Section $script:AllSections

        $r.Computer               | Should -Be 'srv1'
        $r.Status                 | Should -Be 'Success'
        $r.System.OsCaption       | Should -Be 'Server 2019'
        $r.Hardware.MemoryTotalGB | Should -Be 64.0
        @($r.CollectedSections).Count | Should -Be 15
    }

    It 'omits sections not in -Section list' {
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}

        Mock -ModuleName 'PSServerFacts' Get-RemoteSystem               { [pscustomobject]@{ OsCaption='Server 2019'; OsVersion='10'; OsBuild='1'; InstallDateUtc=$null; LastBootUtc=$null; LastHotfix=$null; Domain='corp'; TimeZone='UTC'; WinRmHttpsCertThumbprint=$null } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteHardware             { [pscustomobject]@{ CpuModel='X'; CpuSockets=1; CpuLogicalCores=1; MemoryTotalGB=1.0 } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteDisks                { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteNetwork              { [pscustomobject]@{ Hostname='x'; Fqdn='x'; Adapters=@() } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteInstalledApplication { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteChocolateyPackage    { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteWindowsFeature       { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemotePermission           { [pscustomobject]@{ Administrators=@(); RemoteDesktopUsers=@(); RemoteManagementUsers=@() } }
        Mock -ModuleName 'PSServerFacts' Get-RemoteService              { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteShare                { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteScheduledTask        { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteLocalUser            { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteFirewallRule         { @() }
        Mock -ModuleName 'PSServerFacts' Get-RemoteIis                  { $null }
        Mock -ModuleName 'PSServerFacts' Get-RemoteCertificate          { @() }

        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -Section 'Services','Shares'

        @($r.CollectedSections) | Should -Be @('Services','Shares')
        $r.PSObject.Properties['Services'] | Should -Not -BeNullOrEmpty
        $r.PSObject.Properties['Shares']   | Should -Not -BeNullOrEmpty
        $r.PSObject.Properties['System']   | Should -BeNullOrEmpty
        $r.PSObject.Properties['Hardware'] | Should -BeNullOrEmpty
        # ServiceAccounts auto-follows Services/Tasks/Iis
        $r.PSObject.Properties['ServiceAccounts'] | Should -Not -BeNullOrEmpty
    }

    It 'omits AdvisoriesComputed when -SkipAdvisories is set' {
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}
        Mock -ModuleName 'PSServerFacts' Get-RemoteSystem { [pscustomobject]@{ OsCaption='Server 2019'; OsVersion='10'; OsBuild='1'; InstallDateUtc=$null; LastBootUtc=$null; LastHotfix=$null; Domain='corp.contoso.com'; TimeZone='UTC'; WinRmHttpsCertThumbprint=$null } }
        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -SkipAdvisories:$true -AdvisoryJson:$false `
            -Section @('System')
        $r.PSObject.Properties['AdvisoriesComputed'] | Should -BeNullOrEmpty
        $r.PSObject.Properties['Advisories']         | Should -BeNullOrEmpty
    }
    It 'attaches empty AdvisoriesComputed by default (no rules wired yet)' {
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}
        Mock -ModuleName 'PSServerFacts' Get-RemoteSystem { [pscustomobject]@{ OsCaption='X'; OsVersion='1'; OsBuild='1'; InstallDateUtc=$null; LastBootUtc=$null; LastHotfix=$null; Domain='x'; TimeZone='UTC'; WinRmHttpsCertThumbprint=$null } }
        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -SkipAdvisories:$false -AdvisoryJson:$true `
            -Section @('System')
        @($r.AdvisoriesComputed).Count | Should -Be 0
        @($r.Advisories).Count         | Should -Be 0
    }

    It 'ScheduledTasks normalization survives a task whose Triggers field is $null' {
        # Regression: tasks with no triggers (on-demand only) used to crash the
        # whole worker because Format-TriggerSummary -Trigger $null binds-fails
        # outside the per-section try/catch. Should now degrade to an empty
        # Triggers array on that task with no fatal error.
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}
        Mock -ModuleName 'PSServerFacts' Get-RemoteScheduledTask {
            @(
                [pscustomobject]@{ TaskPath='\App\'; TaskName='OnDemand'; State='Ready'; RunAs='SYSTEM'; Triggers=$null; Actions=@('cmd.exe /c foo') }
            )
        }
        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$true -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -SkipAdvisories:$true `
            -Section @('ScheduledTasks')
        $r.Status                | Should -Be 'Success'
        @($r.ScheduledTasks).Count | Should -Be 1
        @($r.ScheduledTasks[0].Triggers).Count | Should -Be 0
        $r.ScheduledTasks[0].TaskName | Should -Be 'OnDemand'
    }

    It 'URA filter drops default principals and empty privileges when -IncludeAllUserRights is $false' {
        $session = $script:RealSession
        Mock -ModuleName 'PSServerFacts' New-PSSession { $session }.GetNewClosure()
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}
        # URA collector returns one all-default privilege (SeBackupPrivilege: Admins + BackupOps)
        # and one custom privilege (SeDebugPrivilege: Admins + a custom account).
        Mock -ModuleName 'PSServerFacts' Get-RemoteUserRightsAssignment {
            @(
                [pscustomobject]@{
                    Privilege  = 'SeBackupPrivilege'
                    Principals = @(
                        [pscustomobject]@{ Sid='S-1-5-32-544'; Account='BUILTIN\Administrators'; Type='WellKnown'; Domain=$null; SamAccountName=$null; DistinguishedName=$null; ResolveError=$null },
                        [pscustomobject]@{ Sid='S-1-5-32-551'; Account='BUILTIN\Backup Operators'; Type='WellKnown'; Domain=$null; SamAccountName=$null; DistinguishedName=$null; ResolveError=$null }
                    )
                },
                [pscustomobject]@{
                    Privilege  = 'SeDebugPrivilege'
                    Principals = @(
                        [pscustomobject]@{ Sid='S-1-5-32-544'; Account='BUILTIN\Administrators'; Type='WellKnown'; Domain=$null; SamAccountName=$null; DistinguishedName=$null; ResolveError=$null },
                        [pscustomobject]@{ Sid='S-1-5-21-1111-2222-3333-1001'; Account='CORP\CustomDebugUser'; Type='User'; Domain='corp'; SamAccountName='CustomDebugUser'; DistinguishedName='CN=CustomDebugUser,DC=corp'; ResolveError=$null }
                    )
                }
            )
        }
        $r = Get-ServerFacts -ComputerName 'srv1' `
            -DomainCache $script:DomainCache -DataFiles $script:DataFiles `
            -NtfsDepth Root -NtfsSecurityProvisioning None `
            -IncludeAllServices:$false -IncludeAllShares:$false `
            -IncludeAllScheduledTasks:$false -IncludeAllCertStores:$false `
            -IncludeAllFirewallRules:$false `
            -IncludeAllUserRights:$false `
            -SkipAdvisories:$true `
            -Section @('UserRightsAssignment')

        # SeBackupPrivilege has only defaults — should be dropped entirely
        $ura = @($r.UserRightsAssignment)
        $backup = $ura | Where-Object Privilege -eq 'SeBackupPrivilege'
        $backup | Should -BeNullOrEmpty

        # SeDebugPrivilege: BUILTIN\Administrators is default, custom user should remain
        $debug = $ura | Where-Object Privilege -eq 'SeDebugPrivilege'
        $debug | Should -Not -BeNullOrEmpty
        @($debug.Principals).Count | Should -Be 1
        $debug.Principals[0].Account | Should -Be 'CORP\CustomDebugUser'

        # Flag should be set to false
        $r.UserRightsAssignmentIncludeAll | Should -Be $false
    }
}


