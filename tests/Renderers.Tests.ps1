. $PSScriptRoot/Bootstrap.ps1

Describe 'ConvertTo-ServerFactsMarkdown' {
    It 'matches the golden file for the success fixture' {
        $fixture = Get-Content "$RepoRoot/tests/fixtures/server-success.json" -Raw | ConvertFrom-Json
        $expected = Get-Content "$RepoRoot/tests/golden/server-success.md" -Raw
        $actual   = ConvertTo-ServerFactsMarkdown -Result $fixture
        # Compare normalizing line endings.
        ($actual -replace "`r","").TrimEnd() | Should -Be ($expected -replace "`r","").TrimEnd()
    }
}

Describe 'ConvertTo-ServerFactsMarkdown — Chef section' {
    It 'renders full Chef block when collected and non-null' {
        $result = [pscustomobject]@{
            Computer='srv01'; ScannedAtUtc='2026-05-05T00:00:00Z'; ScannedBy='dom\u'; Status='Success'
            DurationSeconds=1.2; CollectedSections=@('Chef'); Errors=@()
            Chef = [pscustomobject]@{
                Installed=$true; Version='Chef Infra Client 17.10.0'
                NodeName='srv01.prod.example.com'; ChefServerUrl='https://chef.example.com/organizations/myorg'
                Environment='prod'; ValidationClient='myorg-validator'
                RunList=@('role[base]','role[appserver]','recipe[mycookbook::install]')
                AttributeKeys=[pscustomobject]@{ default=@('apache','mysql'); normal=@('mycookbook'); override=@(); automatic=@('fqdn','platform') }
                LastSuccessfulRunUtc='2026-05-04T03:14:22Z'
            }
        }
        $md = ConvertTo-ServerFactsMarkdown -Result $result
        $md | Should -Match '## Chef'
        $md | Should -Match 'srv01\.prod\.example\.com'
        $md | Should -Match '### Run List'
        $md | Should -Match 'role\[base\]'
        $md | Should -Match '### Attribute Keys'
        $md | Should -Match '\| default\s+\| apache, mysql \|'
        $md | Should -Match '\| override\s+\| \*\(none\)\*'
    }

    It 'renders "*(not installed)*" when Chef collected and null' {
        $result = [pscustomobject]@{
            Computer='srv01'; ScannedAtUtc='2026-05-05T00:00:00Z'; ScannedBy='dom\u'; Status='Success'
            DurationSeconds=1.2; CollectedSections=@('Chef'); Errors=@()
            Chef=$null
        }
        $md = ConvertTo-ServerFactsMarkdown -Result $result
        $md | Should -Match '## Chef'
        $md | Should -Match '\*\(not installed\)\*'
    }

    It 'omits Chef section when not collected' {
        $result = [pscustomobject]@{
            Computer='srv01'; ScannedAtUtc='2026-05-05T00:00:00Z'; ScannedBy='dom\u'; Status='Success'
            DurationSeconds=1.2; CollectedSections=@('System'); Errors=@()
            System=[pscustomobject]@{}
        }
        $md = ConvertTo-ServerFactsMarkdown -Result $result
        $md | Should -Not -Match '## Chef'
    }
}

Describe 'ConvertTo-ServerFactsMarkdown — SQL Server section' {
    It 'renders per-instance block with sub-tables' {
        $instance = [pscustomobject]@{
            InstanceName='MSSQLSERVER'; ServerName='srv01\MSSQLSERVER'; InstanceId='MSSQL16.MSSQLSERVER'
            Version='16.0.4085.2'; Edition='Standard Edition (64-bit)'; PatchLevel='CU14'
            Collation='SQL_Latin1_General_CP1_CI_AS'; AuthenticationMode='Mixed'; IsClustered=$false
            InstalledFeatures=@('SQLENGINE','FULLTEXT')
            InstalledUpdates=@(
                [pscustomobject]@{ KB='KB5036343'; Version='16.0.4085.2'; InstalledUtc='2026-04-12T00:00:00Z' }
            )
            ServiceAccounts=[pscustomobject]@{
                Engine=[pscustomobject]@{ Name='MSSQLSERVER'; Account='PROD\sql_engine_svc'; StartMode='Auto'; State='Running' }
                Agent=[pscustomobject]@{ Name='SQLSERVERAGENT'; Account='PROD\sql_agent_svc'; StartMode='Auto'; State='Running' }
                Browser=$null
            }
            Configuration=[pscustomobject]@{
                MaxMemoryMB=65536; MinMemoryMB=16384; MaxDop=8; CostThresholdForParallelism=50
                DefaultDataPath='D:\SQL\Data'; DefaultLogPath='E:\SQL\Log'; BackupDirectory='\\backup\sql$\srv01'
            }
            Logins=@(
                [pscustomobject]@{ Name='sa'; Type='SqlLogin'; Disabled=$true; Locked=$false; ServerRoles=@('sysadmin'); DatabaseAccess=@() },
                [pscustomobject]@{ Name='PROD\dba_team'; Type='WindowsGroup'; Disabled=$false; Locked=$false; ServerRoles=@('sysadmin'); DatabaseAccess=@(
                    [pscustomobject]@{ Database='AppDB'; DatabaseUser='AppDbaUser'; Roles=@('db_owner') }
                ) }
            )
            OrphanDatabaseUsers=@([pscustomobject]@{ Database='OldApp'; DatabaseUser='abandoned_user'; Roles=@('db_owner') })
            LinkedServers=@([pscustomobject]@{ Name='REPORTING_LINK'; Product='SQL Server'; DataSource='rpt-srv01\REPORT'; SecurityMode='SelfMapping' })
            Databases=@(
                [pscustomobject]@{ Name='master'; IsSystem=$true; Collation='SQL_Latin1...'; RecoveryModel='Simple'; CompatibilityLevel=160; Owner='sa'; Status='Normal'; SizeMB=12.5; Files=@() }
                [pscustomobject]@{ Name='AppDB'; IsSystem=$false; Collation='SQL_Latin1...'; RecoveryModel='Full'; CompatibilityLevel=160; Owner='sa'; Status='Normal'; SizeMB=2048; Files=@() }
            )
            DiskLayout=@(
                [pscustomobject]@{ Drive='D:'; Roles=@('UserData'); TotalGB=500; FreeGB=312.4 }
                [pscustomobject]@{ Drive='E:'; Roles=@('UserLog');  TotalGB=200; FreeGB=150.1 }
            )
            AvailabilityGroups=@()
            AgentJobs=@(
                [pscustomobject]@{ Name='DB Backup'; Enabled=$true; Owner='sa'; Category='Database Maintenance'
                    LastRunUtc='2026-05-04T20:00:00Z'; LastRunOutcome='Succeeded'; NextRunUtc='2026-05-05T20:00:00Z'
                    Schedules=@([pscustomobject]@{ Name='Daily 8pm'; Summary='Daily at 20:00' }) }
            )
            Backups=@(
                [pscustomobject]@{ DatabaseName='AppDB'; LastFull=[pscustomobject]@{ BackupAtUtc='2026-05-04T20:00:00Z'; SizeMB=1024; Path='\\backup\sql\AppDB.bak'; DestinationType='Disk' }; LastDiff=$null; LastLog=$null }
            )
            BackupDirectoryAcls=@(
                [pscustomobject]@{ Path='\\backup\sql$\srv01'; PathType='UNC'; Owner='BUILTIN\Administrators'; Inheritance='Enabled'
                    Entries=@([pscustomobject]@{ Account='PROD\sql_engine_svc'; Rights='FullControl'; AccessControlType='Allow'; AppliesTo='ThisFolderSubfoldersAndFiles'; Inherited=$false }) }
            )
            ConnectionMethod='TargetSideDbatools'; LiveQueryAvailable=$true
        }
        $result = [pscustomobject]@{
            Computer='srv01'; ScannedAtUtc='2026-05-05T00:00:00Z'; ScannedBy='dom\u'; Status='Success'
            DurationSeconds=2.5; CollectedSections=@('SqlServer'); Errors=@()
            SqlServer=@($instance)
        }
        $md = ConvertTo-ServerFactsMarkdown -Result $result
        $md | Should -Match '## SQL Server'
        $md | Should -Match '### Instance: MSSQLSERVER'
        $md | Should -Match 'CU14'
        $md | Should -Match '#### Configuration'
        $md | Should -Match '#### Server-Level Logins'
        $md | Should -Match 'AppDB:db_owner'
        $md | Should -Match '#### Orphan Database Users'
        $md | Should -Match '#### Linked Servers'
        $md | Should -Match '#### Disk Layout'
        $md | Should -Match '#### SQL Agent Jobs'
        $md | Should -Match 'Daily at 20:00'
        $md | Should -Match '#### Backup Directory'
        $md | Should -Match 'PROD\\sql_engine_svc'
    }

    It 'omits the SQL Server section entirely when SqlServer collected and null' {
        $result = [pscustomobject]@{
            Computer='srv01'; ScannedAtUtc='2026-05-05T00:00:00Z'; ScannedBy='dom\u'; Status='Success'
            DurationSeconds=1.2; CollectedSections=@('SqlServer'); Errors=@()
            SqlServer=$null
        }
        $md = ConvertTo-ServerFactsMarkdown -Result $result
        $md | Should -Not -Match '## SQL Server'
    }
}

Describe 'Format-RunSummary' {
    It 'renders per-server status table and aggregate sections' {
        $results = @(
            [pscustomobject]@{
                Computer='SRV1'; Status='Success'; DurationSeconds=10.0; Errors=@()
                Services=@(); Shares=@(); ScheduledTasks=@(); Iis=$null
                ServiceAccounts=@([pscustomobject]@{ Account='CORP\msvc'; Type='User'; UsedBy=@([pscustomobject]@{ Kind='Service'; Name='X' }) })
                Certificates=@([pscustomobject]@{ Store='LocalMachine\My'; Subject='CN=x'; Thumbprint='AB'; NotAfterUtc='2026-06-01T00:00:00Z'; DaysUntilExpiry=30; Expired=$false })
            }
            [pscustomobject]@{
                Computer='SRV2'; Status='Failed'; DurationSeconds=2.0
                Errors=@([pscustomobject]@{ Section='Connect'; Message='WinRM down' })
            }
        )
        $md = Format-RunSummary -Results $results -StartedUtc '2026-04-30T14:30:00Z' -FinishedUtc '2026-04-30T14:34:00Z'
        $md | Should -Match 'Servers:\*\* 2'
        $md | Should -Match 'SRV2'
        $md | Should -Match 'WinRM down'
        $md | Should -Match 'CORP\\msvc'
        $md | Should -Match '30 d'
    }
}

Describe 'Format-RunSummary — SQL Server cross-server block' {
    It 'emits SQL block when at least one server collected SqlServer with instances' {
        $r1 = [pscustomobject]@{
            Computer='srv01'; Status='Success'; DurationSeconds=2.5; CollectedSections=@('SqlServer'); Errors=@()
            SqlServer=@([pscustomobject]@{
                InstanceName='MSSQLSERVER'; ServerName='srv01\MSSQLSERVER'; Version='16.0.4085.2'
                Edition='Standard Edition (64-bit)'; ConnectionMethod='TargetSideDbatools'; LiveQueryAvailable=$true
                Databases=@([pscustomobject]@{ Name='AppDB'; IsSystem=$false }, [pscustomobject]@{ Name='master'; IsSystem=$true })
                AvailabilityGroups=@(); LinkedServers=@(); Backups=@()
            })
        }
        $r2 = [pscustomobject]@{
            Computer='srv02'; Status='PartialSuccess'; DurationSeconds=1.8; CollectedSections=@('SqlServer')
            Errors=@([pscustomobject]@{ Section='SqlServer'; Message='Login failed' })
            SqlServer=@([pscustomobject]@{
                InstanceName='REPORT'; ServerName='srv02\REPORT'; Version='15.0.4322.2'
                Edition='Standard Edition (64-bit)'; ConnectionMethod='Failed'; LiveQueryAvailable=$false
                Databases=@(); AvailabilityGroups=@(); LinkedServers=@(); Backups=@()
            })
        }
        $md = Format-RunSummary -Results @($r1,$r2) -StartedUtc '2026-05-05T00:00:00Z' -FinishedUtc '2026-05-05T00:01:00Z'
        $md | Should -Match '## SQL Server \(cross-server\)'
        $md | Should -Match 'Total instances:'
        $md | Should -Match '### Editions'
        $md | Should -Match 'Standard Edition'
        $md | Should -Match '### Versions'
        $md | Should -Match '### Connection failures'
        $md | Should -Match 'srv02\\REPORT'
    }

    It 'omits SQL block when no server has SqlServer instances' {
        $r1 = [pscustomobject]@{
            Computer='srv01'; Status='Success'; DurationSeconds=1.0; CollectedSections=@('System'); Errors=@()
            System=$null
        }
        $md = Format-RunSummary -Results @($r1) -StartedUtc '2026-05-05T00:00:00Z' -FinishedUtc '2026-05-05T00:01:00Z'
        $md | Should -Not -Match '## SQL Server \(cross-server\)'
    }
}
