. $PSScriptRoot/Bootstrap.ps1

Describe 'Format-AdvisorySummaryBlock' {
    It 'returns empty string when no advisories' {
        Format-AdvisorySummaryBlock -Advisories @() | Should -BeNullOrEmpty
    }
    It 'renders heading with counts and a table row per advisory' {
        $adv = @(
            [pscustomobject]@{ Section='Defender'; Severity='Critical'; Rule='DefenderRtDisabled'; Message='Real-time off.';   Context=$null }
            [pscustomobject]@{ Section='Smb';      Severity='Critical'; Rule='Smb1Enabled';        Message='SMB1 enabled.';     Context=$null }
            [pscustomobject]@{ Section='Tls';      Severity='Warning';  Rule='TlsLegacy';          Message='TLS 1.0 enabled.';  Context=$null }
            [pscustomobject]@{ Section='Sys';      Severity='Note';     Rule='HotfixAge';          Message='Last hotfix 73 d.'; Context=$null }
        )
        $md = Format-AdvisorySummaryBlock -Advisories $adv
        $md | Should -Match '## Advisories'
        $md | Should -Match '2 critical'
        $md | Should -Match '1 warning'
        $md | Should -Match '1 note'
        $md | Should -Match 'DefenderRtDisabled'
        $md | Should -Match 'Smb1Enabled'
    }
}

Describe 'Format-AdvisoryInlineLine' {
    It 'returns blockquote line per advisory' {
        $adv = [pscustomobject]@{ Section='PowerPlan'; Severity='Warning'; Rule='PowerPlanNotHighPerf'; Message='Use High Performance.' }
        $line = Format-AdvisoryInlineLine -Advisory $adv
        $line | Should -Match '^> '
        $line | Should -Match 'PowerPlanNotHighPerf'
        $line | Should -Match 'Use High Performance'
        $line | Should -Match ([char]0x2014)
    }
}

Describe 'Test-PowerPlanAdvisory' {
    $script:hpfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    It 'emits no advisory when active scheme is High Performance' {
        $result = [pscustomobject]@{ PowerPlan = [pscustomobject]@{ ActiveSchemeGuid=$hpfGuid; ActiveSchemeName='High Performance' } }
        $roles  = [pscustomobject]@{ IsCriticalRole=$true; HasSqlServer=$true }
        @(Test-PowerPlanAdvisory -Result $result -Roles $roles).Count | Should -Be 0
    }
    It 'emits a Note when active scheme is Balanced on a non-critical host' {
        $result = [pscustomobject]@{ PowerPlan = [pscustomobject]@{ ActiveSchemeGuid='381b4222-f694-41f0-9685-ff5bb260df2e'; ActiveSchemeName='Balanced' } }
        $roles  = [pscustomobject]@{ IsCriticalRole=$false; HasSqlServer=$false }
        $a = @(Test-PowerPlanAdvisory -Result $result -Roles $roles)
        $a.Count       | Should -Be 1
        $a[0].Severity | Should -Be 'Note'
        $a[0].Rule     | Should -Be 'PowerPlanNotHighPerf'
    }
    It 'escalates to Warning on a critical-role host' {
        $result = [pscustomobject]@{ PowerPlan = [pscustomobject]@{ ActiveSchemeGuid='381b4222-f694-41f0-9685-ff5bb260df2e'; ActiveSchemeName='Balanced' } }
        $roles  = [pscustomobject]@{ IsCriticalRole=$true; HasSqlServer=$true }
        (Test-PowerPlanAdvisory -Result $result -Roles $roles).Severity | Should -Be 'Warning'
    }
}

Describe 'Test-PageFileAdvisory' {
    It 'no advisory when not auto-managed' {
        $result = [pscustomobject]@{ PageFile = [pscustomobject]@{ AutomaticManagedPagefile=$false; PageFiles=@(); CrashControl=$null } }
        $roles  = [pscustomobject]@{ HasSqlServer=$true; IsCriticalRole=$true }
        @(Test-PageFileAdvisory -Result $result -Roles $roles).Count | Should -Be 0
    }
    It 'Note when auto-managed on non-SQL host' {
        $result = [pscustomobject]@{ PageFile = [pscustomobject]@{ AutomaticManagedPagefile=$true; PageFiles=@(); CrashControl=$null } }
        $roles  = [pscustomobject]@{ HasSqlServer=$false; IsCriticalRole=$false }
        $a = @(Test-PageFileAdvisory -Result $result -Roles $roles)
        $a.Count       | Should -Be 1
        $a[0].Severity | Should -Be 'Note'
        $a[0].Rule     | Should -Be 'PageFileAutoManaged'
    }
    It 'Warning when auto-managed on SQL host' {
        $result = [pscustomobject]@{ PageFile = [pscustomobject]@{ AutomaticManagedPagefile=$true; PageFiles=@(); CrashControl=$null } }
        $roles  = [pscustomobject]@{ HasSqlServer=$true; IsCriticalRole=$true }
        $a = @(Test-PageFileAdvisory -Result $result -Roles $roles)
        $a[0].Severity | Should -Be 'Warning'
    }
}

Describe 'Test-TlsAdvisory' {
    It 'emits no advisory when all legacy protocols are disabled' {
        $tls = [pscustomobject]@{ Protocols = @(
            [pscustomobject]@{ Name='SSL 3.0'; Side='Server'; Enabled=$false }
            [pscustomobject]@{ Name='TLS 1.0'; Side='Server'; Enabled=$false }
            [pscustomobject]@{ Name='TLS 1.1'; Side='Client'; Enabled=$false }
        ) }
        @(Test-TlsAdvisory -Result ([pscustomobject]@{ Tls=$tls }) -Roles ([pscustomobject]@{})).Count | Should -Be 0
    }
    It 'emits a Warning per TLS 1.0/1.1 enabled' {
        $tls = [pscustomobject]@{ Protocols = @(
            [pscustomobject]@{ Name='TLS 1.0'; Side='Server'; Enabled=$true }
            [pscustomobject]@{ Name='TLS 1.1'; Side='Client'; Enabled=$true }
        ) }
        $a = @(Test-TlsAdvisory -Result ([pscustomobject]@{ Tls=$tls }) -Roles ([pscustomobject]@{}))
        $a.Count | Should -Be 2
        $a | ForEach-Object { $_.Severity | Should -Be 'Warning' }
    }
    It 'emits a Critical per SSL 2.0/3.0 enabled' {
        $tls = [pscustomobject]@{ Protocols = @(
            [pscustomobject]@{ Name='SSL 2.0'; Side='Server'; Enabled=$true }
            [pscustomobject]@{ Name='SSL 3.0'; Side='Server'; Enabled=$true }
        ) }
        $a = @(Test-TlsAdvisory -Result ([pscustomobject]@{ Tls=$tls }) -Roles ([pscustomobject]@{}))
        $a.Count | Should -Be 2
        $a | ForEach-Object { $_.Severity | Should -Be 'Critical' }
    }
}

Describe 'Test-SmbAdvisory' {
    It 'no advisory on hardened defaults' {
        $smb = [pscustomobject]@{ Smb1Enabled=$false; SigningRequired=$true; Smb1ClientInstalled=$false }
        @(Test-SmbAdvisory -Result ([pscustomobject]@{ Smb=$smb }) -Roles ([pscustomobject]@{})).Count | Should -Be 0
    }
    It 'Critical when SMB1 enabled' {
        $smb = [pscustomobject]@{ Smb1Enabled=$true; SigningRequired=$true; Smb1ClientInstalled=$false }
        $a = @(Test-SmbAdvisory -Result ([pscustomobject]@{ Smb=$smb }) -Roles ([pscustomobject]@{}))
        ($a | Where-Object Rule -eq 'Smb1Enabled').Severity | Should -Be 'Critical'
    }
    It 'Warning when signing not required' {
        $smb = [pscustomobject]@{ Smb1Enabled=$false; SigningRequired=$false; Smb1ClientInstalled=$false }
        $a = @(Test-SmbAdvisory -Result ([pscustomobject]@{ Smb=$smb }) -Roles ([pscustomobject]@{}))
        ($a | Where-Object Rule -eq 'SmbSigningNotRequired').Severity | Should -Be 'Warning'
    }
}

Describe 'Test-DefenderAdvisory' {
    It 'no advisory when RT on and no SQL host' {
        $def = [pscustomobject]@{ Engine=[pscustomobject]@{ RealTimeProtectionEnabled=$true }; Exclusions=[pscustomobject]@{ Paths=@(); Extensions=@(); Processes=@() } }
        @(Test-DefenderAdvisory -Result ([pscustomobject]@{ Defender=$def }) -Roles ([pscustomobject]@{ HasSqlServer=$false })).Count | Should -Be 0
    }
    It 'Critical when RT disabled' {
        $def = [pscustomobject]@{ Engine=[pscustomobject]@{ RealTimeProtectionEnabled=$false }; Exclusions=[pscustomobject]@{ Paths=@(); Extensions=@(); Processes=@() } }
        $a = @(Test-DefenderAdvisory -Result ([pscustomobject]@{ Defender=$def }) -Roles ([pscustomobject]@{ HasSqlServer=$false }))
        ($a | Where-Object Rule -eq 'DefenderRtDisabled').Severity | Should -Be 'Critical'
    }
    It 'Warning when SQL host has data files outside the exclusion list' {
        $sql = @([pscustomobject]@{
            Databases = @([pscustomobject]@{
                Files = @([pscustomobject]@{ Path='D:\SQLData\mydb.mdf' }, [pscustomobject]@{ Path='E:\SQLLog\mydb.ldf' })
            })
        })
        $def = [pscustomobject]@{
            Engine=[pscustomobject]@{ RealTimeProtectionEnabled=$true }
            Exclusions=[pscustomobject]@{ Paths=@('D:\SQLData'); Extensions=@(); Processes=@() }
        }
        $a = @(Test-DefenderAdvisory -Result ([pscustomobject]@{ Defender=$def; SqlServer=$sql }) -Roles ([pscustomobject]@{ HasSqlServer=$true }))
        ($a | Where-Object Rule -eq 'DefenderMissingSqlExclusion').Severity | Should -Be 'Warning'
    }
}

Describe 'Test-UserRightsAdvisory' {
    It 'no advisory when only Administrators has SeTcbPrivilege' {
        $ura = @([pscustomobject]@{ Privilege='SeTcbPrivilege'; Principals=@(
            [pscustomobject]@{ Sid='S-1-5-32-544'; Account='BUILTIN\Administrators'; Type='WellKnown' }
        ) })
        @(Test-UserRightsAdvisory -Result ([pscustomobject]@{ UserRightsAssignment=$ura }) -Roles ([pscustomobject]@{})).Count | Should -Be 0
    }
    It 'Critical when a service account has SeTcbPrivilege' {
        $ura = @([pscustomobject]@{ Privilege='SeTcbPrivilege'; Principals=@(
            [pscustomobject]@{ Sid='S-1-5-32-544'; Account='BUILTIN\Administrators'; Type='WellKnown' }
            [pscustomobject]@{ Sid='S-1-5-21-…';  Account='PROD\svc-app';            Type='User'      }
        ) })
        $a = @(Test-UserRightsAdvisory -Result ([pscustomobject]@{ UserRightsAssignment=$ura }) -Roles ([pscustomobject]@{}))
        ($a | Where-Object Rule -eq 'TcbPrivilegeOnNonAdmin').Severity | Should -Be 'Critical'
    }
}

Describe 'Test-PendingRebootAdvisory' {
    It 'emits no advisory when Any=false' {
        $result = [pscustomobject]@{ PendingReboot = [pscustomobject]@{ Any=$false } }
        $roles  = [pscustomobject]@{ IsCriticalRole=$false }
        @(Test-PendingRebootAdvisory -Result $result -Roles $roles).Count | Should -Be 0
    }
    It 'emits a Note when Any=true' {
        $result = [pscustomobject]@{ PendingReboot = [pscustomobject]@{
            Any=$true; ComponentBasedServicing=$false; WindowsUpdate=$true
            PendingFileRenameOps=$false; ComputerNameChange=$false; CcmClientSDK=$false
        }}
        $roles  = [pscustomobject]@{ IsCriticalRole=$false }
        $a = @(Test-PendingRebootAdvisory -Result $result -Roles $roles)
        $a.Count       | Should -Be 1
        $a[0].Severity | Should -Be 'Note'
        $a[0].Rule     | Should -Be 'PendingRebootFlag'
        $a[0].Section  | Should -Be 'PendingReboot'
        $a[0].Message  | Should -Match 'Windows Update'
    }
}

Describe 'Test-SystemAdvisory' {
    It 'no advisory when LastHotfix is within 60 days' {
        $sys = [pscustomobject]@{ LastHotfix = [pscustomobject]@{ InstalledOn = (Get-Date).AddDays(-30); HotFixID='KB1' } }
        @(Test-SystemAdvisory -Result ([pscustomobject]@{ System=$sys }) -Roles ([pscustomobject]@{})).Count | Should -Be 0
    }
    It 'Note when LastHotfix is between 60 and 90 days' {
        $sys = [pscustomobject]@{ LastHotfix = [pscustomobject]@{ InstalledOn = (Get-Date).AddDays(-75); HotFixID='KB1' } }
        (Test-SystemAdvisory -Result ([pscustomobject]@{ System=$sys }) -Roles ([pscustomobject]@{})).Severity | Should -Be 'Note'
    }
    It 'Warning when LastHotfix is over 90 days' {
        $sys = [pscustomobject]@{ LastHotfix = [pscustomobject]@{ InstalledOn = (Get-Date).AddDays(-100); HotFixID='KB1' } }
        (Test-SystemAdvisory -Result ([pscustomobject]@{ System=$sys }) -Roles ([pscustomobject]@{})).Severity | Should -Be 'Warning'
    }
    It 'no advisory when LastHotfix is missing' {
        @(Test-SystemAdvisory -Result ([pscustomobject]@{ System = [pscustomobject]@{ LastHotfix = $null } }) -Roles ([pscustomobject]@{})).Count | Should -Be 0
    }
}
