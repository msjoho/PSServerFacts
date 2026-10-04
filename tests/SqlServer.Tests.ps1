. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-SqlInstanceList' {
    It 'returns empty array when registry key absent' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Invoke-Command { @() } -ParameterFilter { $true }
            $r = @(Get-SqlInstanceList -Session $session -ServerName 'srv01')
            $r -is [array] | Should -BeTrue
            $r.Count       | Should -Be 0
        } finally { Remove-PSSession $session }
    }

    It 'returns one instance for default install' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Invoke-Command {
                @([pscustomobject]@{ InstanceName='MSSQLSERVER'; InstanceId='MSSQL16.MSSQLSERVER' })
            } -ParameterFilter { $true }
            $r = @(Get-SqlInstanceList -Session $session -ServerName 'srv01')
            $r.Count            | Should -Be 1
            $r[0].InstanceName  | Should -Be 'MSSQLSERVER'
            $r[0].InstanceId    | Should -Be 'MSSQL16.MSSQLSERVER'
            $r[0].ServerName    | Should -Be 'srv01'
        } finally { Remove-PSSession $session }
    }

    It 'returns multiple instances for side-by-side install' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Invoke-Command {
                @(
                    [pscustomobject]@{ InstanceName='MSSQLSERVER'; InstanceId='MSSQL16.MSSQLSERVER' },
                    [pscustomobject]@{ InstanceName='REPORT';      InstanceId='MSSQL15.REPORT' }
                )
            } -ParameterFilter { $true }
            $r = @(Get-SqlInstanceList -Session $session -ServerName 'srv01')
            $r.Count           | Should -Be 2
            $r[1].InstanceName | Should -Be 'REPORT'
            $r[1].ServerName   | Should -Be 'srv01\REPORT'
        } finally { Remove-PSSession $session }
    }
}

Describe 'Get-SqlRegistryFacts' {
    It 'returns Setup, Updates, Features, ServiceAccounts, DefaultPaths' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Invoke-Command {
                [pscustomobject]@{
                    Version           = '16.0.4085.2'
                    Edition           = 'Standard Edition (64-bit)'
                    EditionType       = 'Standard'
                    PatchLevel        = 'CU14'
                    Updates           = @(
                        [pscustomobject]@{ KB='KB5036343'; Version='16.0.4085.2'; InstalledUtc='2026-04-12T00:00:00Z' }
                    )
                    InstalledFeatures = @('SQLENGINE','FULLTEXT','REPL')
                    ServiceAccounts   = [pscustomobject]@{
                        Engine  = [pscustomobject]@{ Name='MSSQLSERVER';    Account='PROD\sql_engine_svc'; StartMode='Auto';   State='Running' }
                        Agent   = [pscustomobject]@{ Name='SQLSERVERAGENT'; Account='PROD\sql_agent_svc';  StartMode='Auto';   State='Running' }
                        Browser = [pscustomobject]@{ Name='SQLBrowser';     Account='NT AUTHORITY\LocalService'; StartMode='Manual'; State='Stopped' }
                    }
                    DefaultDataPath = 'D:\SQL\Data'
                    DefaultLogPath  = 'E:\SQL\Log'
                }
            } -ParameterFilter { $true }
            $r = Get-SqlRegistryFacts -Session $session -InstanceName 'MSSQLSERVER' -InstanceId 'MSSQL16.MSSQLSERVER'
            $r.Version                  | Should -Be '16.0.4085.2'
            $r.Edition                  | Should -Match 'Standard'
            $r.PatchLevel               | Should -Be 'CU14'
            $r.InstalledFeatures        | Should -Contain 'SQLENGINE'
            @($r.Updates).Count         | Should -Be 1
            @($r.Updates)[0].KB         | Should -Be 'KB5036343'
            $r.ServiceAccounts.Engine.Account | Should -Be 'PROD\sql_engine_svc'
            $r.DefaultDataPath          | Should -Be 'D:\SQL\Data'
        } finally { Remove-PSSession $session }
    }
}

Describe 'Connect-SqlInstance' {
    BeforeAll {
        $script:fakeSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll { Remove-PSSession $fakeSession }

    It 'connects from jumphost when dbatools is available' {
        Mock -ModuleName 'PSServerFacts' Get-Module {
            [pscustomobject]@{ Name = 'dbatools' }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'dbatools' }
        Mock -ModuleName 'PSServerFacts' Connect-DbaInstance {
            [pscustomobject]@{ Name='srv01'; Connected=$true }
        }
        $r = Connect-SqlInstance -Session $fakeSession -ComputerName 'srv01' -InstanceName 'MSSQLSERVER'
        $r.ConnectionMethod  | Should -Be 'JumphostSideDbatools'
        $r.Error             | Should -BeNullOrEmpty
        $r.ConnectedInstance | Should -Not -BeNullOrEmpty
    }

    It 'returns RegistryOnly when dbatools missing on jumphost' {
        Mock -ModuleName 'PSServerFacts' Get-Module { @() } -ParameterFilter { $ListAvailable -and $Name -eq 'dbatools' }
        $r = Connect-SqlInstance -Session $fakeSession -ComputerName 'srv01' -InstanceName 'MSSQLSERVER'
        $r.ConnectionMethod | Should -Be 'RegistryOnly'
        $r.ConnectedInstance | Should -BeNullOrEmpty
        $r.Error             | Should -Match 'dbatools'
    }

    It 'returns Failed when Connect-DbaInstance throws' {
        Mock -ModuleName 'PSServerFacts' Get-Module {
            [pscustomobject]@{ Name = 'dbatools' }
        } -ParameterFilter { $ListAvailable -and $Name -eq 'dbatools' }
        Mock -ModuleName 'PSServerFacts' Connect-DbaInstance { throw 'Login failed' }
        $r = Connect-SqlInstance -Session $fakeSession -ComputerName 'srv01' -InstanceName 'MSSQLSERVER'
        $r.ConnectionMethod | Should -Be 'Failed'
        $r.Error            | Should -Match 'Login failed'
    }
}

Describe 'Get-SqlLiveData' {
    BeforeAll {
        Mock -ModuleName 'PSServerFacts' Get-DbaInstanceProperty {
            @(
                [pscustomobject]@{ Name='Collation';                    Value='SQL_Latin1_General_CP1_CI_AS' },
                [pscustomobject]@{ Name='MaxMemory';                    Value=65536 },
                [pscustomobject]@{ Name='MinMemory';                    Value=16384 },
                [pscustomobject]@{ Name='MaxDop';                       Value=8 },
                [pscustomobject]@{ Name='CostThresholdForParallelism';  Value=50 },
                [pscustomobject]@{ Name='IsClustered';                  Value=$false },
                [pscustomobject]@{ Name='LoginMode';                    Value='Mixed' },
                [pscustomobject]@{ Name='BackupDirectory';              Value='\\backup\sql$\srv01' }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaLogin {
            @(
                [pscustomobject]@{ Name='sa';            LoginType='SqlLogin';     IsDisabled=$true;  IsLocked=$false },
                [pscustomobject]@{ Name='PROD\dba_team'; LoginType='WindowsGroup'; IsDisabled=$false; IsLocked=$false }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaServerRoleMember {
            @(
                [pscustomobject]@{ Login='sa';            Role='sysadmin' },
                [pscustomobject]@{ Login='PROD\dba_team'; Role='sysadmin' },
                [pscustomobject]@{ Login='PROD\dba_team'; Role='securityadmin' }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaDbUser {
            @(
                [pscustomobject]@{ Database='AppDB';    Name='AppDbaUser';    Login='PROD\dba_team' },
                [pscustomobject]@{ Database='ConfigDB'; Name='ConfigDbaUser'; Login='PROD\dba_team' },
                [pscustomobject]@{ Database='OldApp';   Name='abandoned_user'; Login=$null }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaDbRoleMember {
            @(
                [pscustomobject]@{ Database='AppDB';    UserName='AppDbaUser';    Role='db_owner' },
                [pscustomobject]@{ Database='ConfigDB'; UserName='ConfigDbaUser'; Role='db_datareader' },
                [pscustomobject]@{ Database='ConfigDB'; UserName='ConfigDbaUser'; Role='db_datawriter' },
                [pscustomobject]@{ Database='OldApp';   UserName='abandoned_user'; Role='db_owner' }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaLinkedServer {
            @(
                [pscustomobject]@{ Name='REPORTING_LINK'; ProductName='SQL Server'; DataSource='rpt-srv01\REPORT'; SecurityMode='SelfMapping' }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaDatabase {
            @(
                [pscustomobject]@{ Name='master'; IsSystemObject=$true;  Collation='SQL_Latin1_General_CP1_CI_AS'; RecoveryModel='Simple'; CompatibilityLevel='Version160'; Owner='sa'; Status='Normal'; SizeMB=12.5 },
                [pscustomobject]@{ Name='tempdb'; IsSystemObject=$true;  Collation='SQL_Latin1_General_CP1_CI_AS'; RecoveryModel='Simple'; CompatibilityLevel='Version160'; Owner='sa'; Status='Normal'; SizeMB=64.0 },
                [pscustomobject]@{ Name='AppDB';  IsSystemObject=$false; Collation='SQL_Latin1_General_CP1_CI_AS'; RecoveryModel='Full';   CompatibilityLevel='Version160'; Owner='sa'; Status='Normal'; SizeMB=2048 }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaDbFile {
            @(
                [pscustomobject]@{ Database='master'; TypeDescription='ROWS'; LogicalName='master';  PhysicalName='D:\SQL\Data\master.mdf';  SizeMB=8.0 },
                [pscustomobject]@{ Database='master'; TypeDescription='LOG';  LogicalName='mastlog'; PhysicalName='E:\SQL\Log\mastlog.ldf';  SizeMB=4.5 },
                [pscustomobject]@{ Database='tempdb'; TypeDescription='ROWS'; LogicalName='tempdev'; PhysicalName='T:\TempDb\tempdev.mdf';   SizeMB=32.0 },
                [pscustomobject]@{ Database='tempdb'; TypeDescription='LOG';  LogicalName='templog'; PhysicalName='U:\TempLog\templog.ldf';  SizeMB=32.0 },
                [pscustomobject]@{ Database='AppDB';  TypeDescription='ROWS'; LogicalName='AppDB';   PhysicalName='D:\SQL\Data\AppDB.mdf';   SizeMB=1024 },
                [pscustomobject]@{ Database='AppDB';  TypeDescription='LOG';  LogicalName='AppDBLog';PhysicalName='E:\SQL\Log\AppDB.ldf';    SizeMB=1024 }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaAvailabilityGroup { @() }
        Mock -ModuleName 'PSServerFacts' Get-DbaAgReplica         { @() }
        Mock -ModuleName 'PSServerFacts' Get-DbaAgListener        { @() }
        Mock -ModuleName 'PSServerFacts' Get-DbaAgDatabase        { @() }
        Mock -ModuleName 'PSServerFacts' Get-DbaAgentJob {
            $sched = [pscustomobject]@{
                Name='Daily 8pm'; IsEnabled=$true; FrequencyType='Daily'; FrequencyInterval=1
                ActiveStartTimeOfDay=[timespan]'20:00:00'; FrequencySubdayType='Once'
            }
            @(
                [pscustomobject]@{
                    Name='DB Backup - System'; IsEnabled=$true; OwnerLoginName='sa'
                    Category='Database Maintenance'; LastRunDate=[datetime]'2026-05-04T20:00:00Z'
                    LastRunOutcome='Succeeded'; NextRunDate=[datetime]'2026-05-05T20:00:00Z'
                    JobSchedules=@($sched)
                }
            )
        }
        Mock -ModuleName 'PSServerFacts' Get-DbaDbBackupHistory {
            @(
                [pscustomobject]@{ Database='AppDB'; Type='Full'; End=[datetime]'2026-05-04T20:00:00Z'; Path=@('\\backup\sql\AppDB_full.bak'); TotalSize=[long](1024*1024*1024); DeviceType='Disk' }
            )
        }
    }

    It 'aggregates Configuration, Logins (with DatabaseAccess), Linked, Databases, AvailabilityGroups (empty), AgentJobs (with rendered schedule), Backups' {
        $sql = [pscustomobject]@{ Name='localhost' }
        $r = Get-SqlLiveData -ConnectedInstance $sql

        $r.Configuration.Collation                    | Should -Be 'SQL_Latin1_General_CP1_CI_AS'
        $r.Configuration.MaxMemoryMB                  | Should -Be 65536
        $r.Configuration.BackupDirectory              | Should -Be '\\backup\sql$\srv01'
        $r.AuthenticationMode                         | Should -Be 'Mixed'
        $r.IsClustered                                | Should -Be $false

        $logins = @($r.Logins)
        $logins.Count                                 | Should -Be 2
        $sa = $logins | Where-Object Name -eq 'sa'
        $sa.ServerRoles                               | Should -Be @('sysadmin')
        @($sa.DatabaseAccess).Count                   | Should -Be 0
        $dba = $logins | Where-Object Name -eq 'PROD\dba_team'
        $dba.ServerRoles                              | Should -Contain 'securityadmin'
        @($dba.DatabaseAccess).Count                  | Should -Be 2
        ($dba.DatabaseAccess | Where-Object Database -eq 'AppDB').Roles    | Should -Be @('db_owner')
        ($dba.DatabaseAccess | Where-Object Database -eq 'ConfigDB').Roles | Should -Contain 'db_datareader'

        @($r.OrphanDatabaseUsers).Count               | Should -Be 1
        @($r.OrphanDatabaseUsers)[0].Database         | Should -Be 'OldApp'
        @($r.OrphanDatabaseUsers)[0].DatabaseUser     | Should -Be 'abandoned_user'
        @($r.OrphanDatabaseUsers)[0].Roles            | Should -Be @('db_owner')

        @($r.LinkedServers).Count                     | Should -Be 1
        @($r.LinkedServers)[0].Name                   | Should -Be 'REPORTING_LINK'

        @($r.Databases).Count                         | Should -Be 3
        $appDb = $r.Databases | Where-Object Name -eq 'AppDB'
        $appDb.IsSystem                               | Should -Be $false
        @($appDb.Files).Count                         | Should -Be 2
        ($appDb.Files | Where-Object Type -eq 'Data').PhysicalPath | Should -Be 'D:\SQL\Data\AppDB.mdf'

        @($r.AvailabilityGroups).Count                | Should -Be 0

        @($r.AgentJobs).Count                         | Should -Be 1
        @($r.AgentJobs)[0].Schedules[0].Summary       | Should -Be 'Daily at 20:00'

        @($r.Backups).Count                           | Should -Be 1
        @($r.Backups)[0].DatabaseName                 | Should -Be 'AppDB'
        @($r.Backups)[0].LastFull.SizeMB              | Should -BeGreaterThan 0
        @($r.Backups)[0].LastFull.DestinationType     | Should -Be 'Disk'
    }
}

Describe 'Get-SqlDiskLayout' {
    It 'categorizes UserData/UserLog/TempDbData/TempDbLog/SystemData/SystemLog by drive' {
        $databases = @(
            [pscustomobject]@{ Name='master'; IsSystem=$true; Files=@(
                [pscustomobject]@{ Type='Data'; PhysicalPath='D:\SQL\Data\master.mdf' }
                [pscustomobject]@{ Type='Log';  PhysicalPath='E:\SQL\Log\mastlog.ldf' }
            )}
            [pscustomobject]@{ Name='tempdb'; IsSystem=$true; Files=@(
                [pscustomobject]@{ Type='Data'; PhysicalPath='T:\Temp\tempdev.mdf' }
                [pscustomobject]@{ Type='Log';  PhysicalPath='U:\TempLog\templog.ldf' }
            )}
            [pscustomobject]@{ Name='AppDB'; IsSystem=$false; Files=@(
                [pscustomobject]@{ Type='Data'; PhysicalPath='D:\SQL\Data\AppDB.mdf' }
                [pscustomobject]@{ Type='Log';  PhysicalPath='E:\SQL\Log\AppDB.ldf' }
            )}
        )
        $disks = @(
            [pscustomobject]@{ Drive='C:'; SizeGB=120; FreeGB=80 },
            [pscustomobject]@{ Drive='D:'; SizeGB=500; FreeGB=312.4 },
            [pscustomobject]@{ Drive='E:'; SizeGB=200; FreeGB=150.1 },
            [pscustomobject]@{ Drive='T:'; SizeGB=64;  FreeGB=40 },
            [pscustomobject]@{ Drive='U:'; SizeGB=32;  FreeGB=20 }
        )
        $r = @(Get-SqlDiskLayout -Databases $databases -Disks $disks)
        ($r | Where-Object Drive -eq 'D:').Roles | Should -Contain 'UserData'
        ($r | Where-Object Drive -eq 'D:').Roles | Should -Contain 'SystemData'
        ($r | Where-Object Drive -eq 'E:').Roles | Should -Contain 'UserLog'
        ($r | Where-Object Drive -eq 'E:').Roles | Should -Contain 'SystemLog'
        ($r | Where-Object Drive -eq 'T:').Roles | Should -Be @('TempDbData')
        ($r | Where-Object Drive -eq 'U:').Roles | Should -Be @('TempDbLog')
        ($r | Where-Object Drive -eq 'D:').TotalGB | Should -Be 500
        ($r | Where-Object Drive -eq 'D:').FreeGB  | Should -Be 312.4
    }

    It 'returns empty array when databases is empty' {
        $r = @(Get-SqlDiskLayout -Databases @() -Disks @())
        $r -is [array] | Should -BeTrue
        $r.Count       | Should -Be 0
    }
}

Describe 'Get-RemoteSqlServer' {
    It 'returns null when no instances detected' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Get-SqlInstanceList { @() }
            Get-RemoteSqlServer -Session $session -ComputerName 'srv01' | Should -BeNullOrEmpty
        } finally { Remove-PSSession $session }
    }

    It 'composes per-instance object with Tier 1 + Tier 2 + DiskLayout + BackupDirectoryAcls' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Get-SqlInstanceList {
                @([pscustomobject]@{ InstanceName='MSSQLSERVER'; InstanceId='MSSQL16.MSSQLSERVER'; ServerName='srv01' })
            }
            Mock -ModuleName 'PSServerFacts' Get-SqlRegistryFacts {
                [pscustomobject]@{
                    Version='16.0.4085.2'; Edition='Standard Edition (64-bit)'; EditionType='Standard'; PatchLevel='CU14'
                    Updates=@(); InstalledFeatures=@('SQLENGINE')
                    ServiceAccounts=[pscustomobject]@{ Engine=$null; Agent=$null; Browser=$null }
                    DefaultDataPath='D:\SQL\Data'; DefaultLogPath='E:\SQL\Log'
                }
            }
            Mock -ModuleName 'PSServerFacts' Connect-SqlInstance {
                [pscustomobject]@{
                    ConnectedInstance = [pscustomobject]@{ Name='localhost' }
                    ConnectionMethod  = 'TargetSideDbatools'
                    Error             = $null
                    UseSession        = $null
                }
            }
            Mock -ModuleName 'PSServerFacts' Get-SqlLiveData {
                [pscustomobject]@{
                    Configuration       = [pscustomobject]@{ MaxMemoryMB=65536; BackupDirectory='\\backup\sql$\srv01' }
                    Collation           = 'SQL_Latin1_General_CP1_CI_AS'
                    AuthenticationMode  = 'Mixed'
                    IsClustered         = $false
                    Logins              = @()
                    OrphanDatabaseUsers = @()
                    LinkedServers       = @()
                    Databases           = @([pscustomobject]@{
                        Name='AppDB'; IsSystem=$false; Files=@(
                            [pscustomobject]@{ Type='Data'; PhysicalPath='D:\SQL\Data\AppDB.mdf' }
                        )
                    })
                    AvailabilityGroups  = @()
                    AgentJobs           = @()
                    Backups             = @()
                }
            }
            Mock -ModuleName 'PSServerFacts' Get-SqlDiskLayout {
                @([pscustomobject]@{ Drive='D:'; Roles=@('UserData'); TotalGB=500; FreeGB=312.4 })
            }
            Mock -ModuleName 'PSServerFacts' Get-SqlBackupDirectoryAcl {
                @([pscustomobject]@{ Path='\\backup\sql$\srv01'; PathType='UNC'; Owner='BUILTIN\Administrators'; Inheritance='Enabled'; Entries=@() })
            }

            $r = @(Get-RemoteSqlServer -Session $session -ComputerName 'srv01' -Disks @([pscustomobject]@{ Drive='D:'; SizeGB=500; FreeGB=312.4 }))
            $r.Count                              | Should -Be 1
            $r[0].InstanceName                    | Should -Be 'MSSQLSERVER'
            $r[0].ServerName                      | Should -Be 'srv01'
            $r[0].Version                         | Should -Be '16.0.4085.2'
            $r[0].PatchLevel                      | Should -Be 'CU14'
            $r[0].Configuration.MaxMemoryMB       | Should -Be 65536
            @($r[0].DiskLayout).Count             | Should -Be 1
            @($r[0].BackupDirectoryAcls).Count    | Should -Be 1
            $r[0].ConnectionMethod                | Should -Be 'TargetSideDbatools'
            $r[0].LiveQueryAvailable              | Should -Be $true
        } finally { Remove-PSSession $session }
    }

    It 'emits RegistryOnly per-instance object when dbatools missing' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Get-SqlInstanceList {
                @([pscustomobject]@{ InstanceName='MSSQLSERVER'; InstanceId='MSSQL16.MSSQLSERVER'; ServerName='srv01' })
            }
            Mock -ModuleName 'PSServerFacts' Get-SqlRegistryFacts {
                [pscustomobject]@{
                    Version='16.0.4085.2'; Edition='Std'; EditionType='Standard'; PatchLevel='CU14'
                    Updates=@(); InstalledFeatures=@()
                    ServiceAccounts=[pscustomobject]@{ Engine=$null; Agent=$null; Browser=$null }
                    DefaultDataPath=$null; DefaultLogPath=$null
                }
            }
            Mock -ModuleName 'PSServerFacts' Connect-SqlInstance {
                [pscustomobject]@{ ConnectedInstance=$null; ConnectionMethod='RegistryOnly'; Error='dbatools not available'; UseSession=$null }
            }

            $r = @(Get-RemoteSqlServer -Session $session -ComputerName 'srv01')
            $r[0].ConnectionMethod        | Should -Be 'RegistryOnly'
            $r[0].LiveQueryAvailable      | Should -Be $false
            @($r[0].Logins).Count         | Should -Be 0
            $r[0].Configuration           | Should -BeNullOrEmpty
        } finally { Remove-PSSession $session }
    }
}

Describe 'Get-SqlBackupDirectoryAcl' {
    BeforeAll {
        # Mock the primitives the probe scriptblock uses. Both jumphost-side (& $probeAcl)
        # and target-side (Invoke-Command -ScriptBlock $probeAcl) paths run the same body,
        # but only jumphost-side hits these mocks — Invoke-Command crosses a boundary.
        Mock -ModuleName 'PSServerFacts' Test-Path { $true } -ParameterFilter { $LiteralPath }
        Mock -ModuleName 'PSServerFacts' Get-Command { $null } -ParameterFilter { $Name -eq 'Get-NTFSAccess' }
        Mock -ModuleName 'PSServerFacts' Get-Acl {
            [pscustomobject]@{
                Owner = 'BUILTIN\Administrators'
                AreAccessRulesProtected = $false
                Access = @(
                    [pscustomobject]@{ IdentityReference='PROD\sql_engine_svc';  FileSystemRights='FullControl'; AccessControlType='Allow'; IsInherited=$false; InheritanceFlags='ContainerInherit, ObjectInherit'; PropagationFlags='None' },
                    [pscustomobject]@{ IdentityReference='NT AUTHORITY\SYSTEM';  FileSystemRights='FullControl'; AccessControlType='Allow'; IsInherited=$true;  InheritanceFlags='ContainerInherit, ObjectInherit'; PropagationFlags='None' },
                    [pscustomobject]@{ IdentityReference='PROD\sql_refresh_svc'; FileSystemRights='Modify';      AccessControlType='Allow'; IsInherited=$false; InheritanceFlags='ContainerInherit, ObjectInherit'; PropagationFlags='None' }
                )
            }
        }
        # Local-path target-side path goes via Invoke-Command — mock that to return
        # an analogous probe shape so the local case still produces a result.
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Path = $ArgumentList[0]; PathType = 'Local'
                Owner = 'BUILTIN\Administrators'; Inheritance = 'Enabled'
                SourceKind = 'GetAcl'
                RawAces = @(
                    [pscustomobject]@{ IdentityReference='PROD\local_user'; FileSystemRights='FullControl'; AccessControlType='Allow'; IsInherited=$false; InheritanceFlags='None'; PropagationFlags='None' }
                )
            }
        } -ParameterFilter { $Session -and $ScriptBlock }
    }

    It 'reads UNC ACL from jumphost and filters to non-inherited only' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            $r = @(Get-SqlBackupDirectoryAcl -Session $session -BackupDirectory '\\backup\sql$\srv01')
            $r.Count                  | Should -Be 1
            $r[0].Path                | Should -Be '\\backup\sql$\srv01'
            $r[0].PathType            | Should -Be 'UNC'
            $r[0].ReadFrom            | Should -Be 'Jumphost'
            @($r[0].Entries).Count    | Should -Be 2
            @($r[0].Entries).Account  | Should -Not -Contain 'NT AUTHORITY\SYSTEM'
        } finally { Remove-PSSession $session }
    }

    It 'reads local-path ACL from target' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            $r = @(Get-SqlBackupDirectoryAcl -Session $session -BackupDirectory 'D:\Backup')
            $r.Count          | Should -Be 1
            $r[0].PathType    | Should -Be 'Local'
            $r[0].ReadFrom    | Should -Be 'Target'
        } finally { Remove-PSSession $session }
    }

    It 'returns empty array when BackupDirectory is null' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            $r = @(Get-SqlBackupDirectoryAcl -Session $session -BackupDirectory $null)
            $r -is [array] | Should -BeTrue
            $r.Count       | Should -Be 0
        } finally { Remove-PSSession $session }
    }

    It 'splits semicolon-separated path list (UNC + local)' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            $r = @(Get-SqlBackupDirectoryAcl -Session $session -BackupDirectory 'D:\Backup;\\backup\sql$\srv01')
            $r.Count          | Should -Be 2
            ($r | Where-Object PathType -eq 'UNC').ReadFrom   | Should -Be 'Jumphost'
            ($r | Where-Object PathType -eq 'Local').ReadFrom | Should -Be 'Target'
        } finally { Remove-PSSession $session }
    }
}

