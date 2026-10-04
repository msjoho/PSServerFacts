. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteUserRightsAssignment' {
    BeforeAll {
        $script:RealSession = New-PSSession -UseWindowsPowerShell
        $script:DomainCache = [hashtable]::Synchronized(@{ 'BUILTIN'='BUILTIN' })
    }
    AfterAll { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'parses secedit output into per-privilege SID lists' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @(
                'SeTcbPrivilege = *S-1-5-32-544',
                'SeServiceLogonRight = *S-1-5-20,*S-1-5-32-544',
                'SeBackupPrivilege = *S-1-5-32-544'
            )
        }
        Mock -ModuleName 'PSServerFacts' Resolve-AdPrincipal {
            param($Sid, $Account, $DomainCache)
            [pscustomobject]@{ Sid=$Sid; Account=$Account; Type='WellKnown'; Domain=$null; SamAccountName=$null; DistinguishedName=$null; ResolveError=$null }
        }
        $r = Get-RemoteUserRightsAssignment -Session $script:RealSession -DomainCache $script:DomainCache
        @($r).Count                                                              | Should -Be 3
        ($r | Where-Object Privilege -eq 'SeTcbPrivilege').Principals.Count      | Should -Be 1
        ($r | Where-Object Privilege -eq 'SeServiceLogonRight').Principals.Count | Should -Be 2
    }

    It 'does NOT attach .Members when -ExpandMembers is omitted' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            @('SeBackupPrivilege = *S-1-5-32-544')
        }
        Mock -ModuleName 'PSServerFacts' Resolve-AdPrincipal {
            param($Sid, $Account, $DomainCache)
            $type = if ($Account -match '^BUILTIN\\') { 'WellKnown' } else { 'LocalAccount' }
            [pscustomobject]@{ Sid=$Sid; Account=$Account; Type=$type; Domain=$null; SamAccountName=$Account; DistinguishedName=$null; ResolveError=$null }
        }
        $r = Get-RemoteUserRightsAssignment -Session $script:RealSession -DomainCache $script:DomainCache
        $backup = $r | Where-Object Privilege -eq 'SeBackupPrivilege'
        $admPrincipal = $backup.Principals | Where-Object Account -eq 'BUILTIN\Administrators'
        $admPrincipal | Should -Not -BeNullOrEmpty
        # No local-group enumeration should have run — Members property absent
        $admPrincipal.PSObject.Properties['Members'] | Should -BeNullOrEmpty
    }

    It 'attaches .Members to BUILTIN\ group principals when -ExpandMembers is set' {
        # First Invoke-Command call returns secedit lines (string array).
        # Second Invoke-Command call returns the local-group member lookup hashtable.
        # We use a script-scope counter that the mock scriptblock can see.
        $script:_UraTestCallCount = 0
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            $script:_UraTestCallCount++
            if ($script:_UraTestCallCount -eq 1) {
                # secedit lines — principal is BUILTIN\Administrators (S-1-5-32-544)
                @('SeBackupPrivilege = *S-1-5-32-544')
            } else {
                # local-group member lookup: Administrators has one member
                @{ 'Administrators' = @([pscustomobject]@{ Sid = 'S-1-5-21-1111-2222-3333-500'; Account = 'MYSERVER\Administrator' }) }
            }
        }
        Mock -ModuleName 'PSServerFacts' Resolve-AdPrincipal {
            param($Sid, $Account, $DomainCache)
            # BUILTIN SIDs get WellKnown type so the BUILTIN\ group detection in the collector fires
            $type = if ($Account -match '^BUILTIN\\') { 'WellKnown' } else { 'LocalAccount' }
            [pscustomobject]@{ Sid=$Sid; Account=$Account; Type=$type; Domain=$null; SamAccountName=$Account; DistinguishedName=$null; ResolveError=$null }
        }
        $r = Get-RemoteUserRightsAssignment -Session $script:RealSession -DomainCache $script:DomainCache -ExpandMembers
        $backup = $r | Where-Object Privilege -eq 'SeBackupPrivilege'
        $admPrincipal = $backup.Principals | Where-Object Account -eq 'BUILTIN\Administrators'
        $admPrincipal | Should -Not -BeNullOrEmpty
        $admPrincipal.PSObject.Properties['Members'] | Should -Not -BeNullOrEmpty
        @($admPrincipal.Members).Count | Should -BeGreaterOrEqual 1
    }
}
