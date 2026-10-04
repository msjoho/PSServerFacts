. $PSScriptRoot/Bootstrap.ps1

Describe 'Test-IsDefaultService' {
    BeforeAll {
        $script:Data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultServices.psd1"
    }
    It 'hides services whose binary is in %SystemRoot%\System32' {
        $svc = [pscustomobject]@{ Name = 'foo'; PathName = 'C:\WINDOWS\System32\svchost.exe -k netsvcs' }
        Test-IsDefaultService -Service $svc -KnownDefaults $Data.KnownDefaults -KnownCustomFalsePositives $Data.KnownCustomFalsePositives | Should -BeTrue
    }
    It 'hides services whose binary is in %SystemRoot%\SysWOW64' {
        $svc = [pscustomobject]@{ Name = 'foo'; PathName = '"C:\WINDOWS\SysWOW64\svc.exe" --x' }
        Test-IsDefaultService -Service $svc -KnownDefaults $Data.KnownDefaults -KnownCustomFalsePositives $Data.KnownCustomFalsePositives | Should -BeTrue
    }
    It 'hides services in KnownDefaults even when path is non-system' {
        $svc = [pscustomobject]@{ Name = 'wuauserv'; PathName = 'D:\weird\wuauserv.exe' }
        Test-IsDefaultService -Service $svc -KnownDefaults $Data.KnownDefaults -KnownCustomFalsePositives $Data.KnownCustomFalsePositives | Should -BeTrue
    }
    It 'shows services whose binary lives in Program Files' {
        $svc = [pscustomobject]@{ Name = 'MyApp'; PathName = '"C:\Program Files\MyApp\svc.exe"' }
        Test-IsDefaultService -Service $svc -KnownDefaults $Data.KnownDefaults -KnownCustomFalsePositives $Data.KnownCustomFalsePositives | Should -BeFalse
    }
    It 'shows custom services in KnownCustomFalsePositives even if in System32' {
        $svc = [pscustomobject]@{ Name = 'CustomSvc'; PathName = 'C:\WINDOWS\System32\customsvc.exe' }
        Test-IsDefaultService -Service $svc -KnownDefaults @() -KnownCustomFalsePositives @('CustomSvc') | Should -BeFalse
    }
    It 'expands env vars in path' {
        $svc = [pscustomobject]@{ Name = 'foo'; PathName = '%SystemRoot%\System32\svchost.exe' }
        Test-IsDefaultService -Service $svc -KnownDefaults $Data.KnownDefaults -KnownCustomFalsePositives $Data.KnownCustomFalsePositives | Should -BeTrue
    }
}

Describe 'Test-IsDefaultShare' {
    BeforeAll {
        $script:Defaults = (Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultShares.psd1").Names
    }
    It 'returns true for ADMIN$' {
        Test-IsDefaultShare -Name 'ADMIN$' -DefaultNames $Defaults | Should -BeTrue
    }
    It 'returns true for letter-drive shares like C$, D$, Z$' {
        foreach ($n in 'C$','D$','Z$') {
            Test-IsDefaultShare -Name $n -DefaultNames $Defaults | Should -BeTrue
        }
    }
    It 'returns false for custom shares' {
        Test-IsDefaultShare -Name 'Finance' -DefaultNames $Defaults | Should -BeFalse
    }
    It 'is case-insensitive' {
        Test-IsDefaultShare -Name 'admin$' -DefaultNames $Defaults | Should -BeTrue
    }
}

Describe 'Test-IsDefaultScheduledTask' {
    BeforeAll {
        $script:Patterns = (Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultTaskPaths.psd1").Patterns
    }
    It 'matches \Microsoft\* paths' {
        Test-IsDefaultScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -Patterns $Patterns | Should -BeTrue
        Test-IsDefaultScheduledTask -TaskPath '\Microsoft\Office\'         -Patterns $Patterns | Should -BeTrue
    }
    It 'does not match custom paths' {
        Test-IsDefaultScheduledTask -TaskPath '\Backups\'   -Patterns $Patterns | Should -BeFalse
        Test-IsDefaultScheduledTask -TaskPath '\'           -Patterns $Patterns | Should -BeFalse
        Test-IsDefaultScheduledTask -TaskPath '\Apps\Sync\' -Patterns $Patterns | Should -BeFalse
    }
}

Describe 'Test-IsDefaultCertIssuer' {
    BeforeAll {
        $script:Issuers = (Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultCertIssuers.psd1").Issuers
    }
    It 'matches public CA issuers as substring' {
        Test-IsDefaultCertIssuer -Issuer 'CN=DigiCert Global Root G2, O=DigiCert Inc, C=US' -DefaultIssuers $Issuers | Should -BeTrue
        Test-IsDefaultCertIssuer -Issuer "CN=Let's Encrypt R3, O=Let's Encrypt, C=US"        -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'matches Microsoft root issuers' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Microsoft Root Certificate Authority 2011' -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'matches legacy Microsoft Authenticode and Time Stamping certs' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Microsoft Authenticode(tm) Root Authority, O=MSFT, C=US' -DefaultIssuers $Issuers | Should -BeTrue
        Test-IsDefaultCertIssuer -Issuer 'OU=Microsoft Time Stamping Service Root, O=Microsoft Trust Network' -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'matches Microsoft Code Signing certs in TrustedPublisher' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Microsoft Code Signing PCA 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US' -DefaultIssuers $Issuers | Should -BeTrue
        Test-IsDefaultCertIssuer -Issuer 'CN=Microsoft Code Signing PCA 2024, O=Microsoft Corporation, C=US' -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'matches Symantec Enterprise Mobile Root for Microsoft' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Symantec Enterprise Mobile Root for Microsoft, O=Symantec Corporation, C=US' -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'matches Go Daddy with and without space' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Go Daddy Root Certificate Authority - G2, O="GoDaddy.com, Inc.", C=US' -DefaultIssuers $Issuers | Should -BeTrue
        Test-IsDefaultCertIssuer -Issuer 'CN=GoDaddy Class 2 CA' -DefaultIssuers $Issuers | Should -BeTrue
    }
    It 'returns false for org-internal issuers' {
        Test-IsDefaultCertIssuer -Issuer 'CN=Contoso Issuing CA 01, DC=corp, DC=contoso, DC=com' -DefaultIssuers $Issuers | Should -BeFalse
    }
}

Describe 'Test-IsDefaultFirewallRule' {
    BeforeAll {
        $script:Prefixes = (Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultFirewallGroupPrefixes.psd1").Prefixes
    }
    It 'returns true for rules with Microsoft-shipped Group' {
        Test-IsDefaultFirewallRule -Group '@FirewallAPI.dll,-25000' -GroupPrefixes $Prefixes | Should -BeTrue
        Test-IsDefaultFirewallRule -Group '@%SystemRoot%\system32\firewallapi.dll,-12345' -GroupPrefixes $Prefixes | Should -BeTrue
    }
    It 'returns true for AppX/UWP package groups' {
        Test-IsDefaultFirewallRule -Group '@{Microsoft.Windows.Cortana_1.11.6.17763_neutral_neutral_cw5n1h2txyewy?ms-resource://Microsoft.Windows.Cortana/resources/PackageDisplayName}' -GroupPrefixes $Prefixes | Should -BeTrue
        Test-IsDefaultFirewallRule -Group '@{Microsoft.AAD.BrokerPlugin_1000.17763.1.0_neutral_neutral_cw5n1h2txyewy?ms-resource://Microsoft.AAD.BrokerPlugin/resources/PackageDisplayName}' -GroupPrefixes $Prefixes | Should -BeTrue
    }
    It 'returns true for ICS, Shell Input, and DiagTrack groups' {
        Test-IsDefaultFirewallRule -Group '@icsvc.dll,-700'        -GroupPrefixes $Prefixes | Should -BeTrue
        Test-IsDefaultFirewallRule -Group 'Shell Input Application' -GroupPrefixes $Prefixes | Should -BeTrue
        Test-IsDefaultFirewallRule -Group 'DiagTrack'               -GroupPrefixes $Prefixes | Should -BeTrue
    }
    It 'returns false when Group is empty (custom rule)' {
        Test-IsDefaultFirewallRule -Group '' -GroupPrefixes $Prefixes | Should -BeFalse
        Test-IsDefaultFirewallRule -Group $null -GroupPrefixes $Prefixes | Should -BeFalse
    }
    It 'returns false for org-defined groups' {
        Test-IsDefaultFirewallRule -Group 'MyApp Rules' -GroupPrefixes $Prefixes | Should -BeFalse
    }
}

Describe 'Test-IsDefaultUserRightPrincipal' {
    BeforeAll {
        $script:Defaults = (Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultUserRights.psd1").Defaults
    }
    It 'returns true for BUILTIN\Administrators on SeBackupPrivilege' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeBackupPrivilege' -Account 'BUILTIN\Administrators' -Defaults $script:Defaults | Should -BeTrue
    }
    It 'returns true for BUILTIN\Backup Operators on SeBackupPrivilege' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeBackupPrivilege' -Account 'BUILTIN\Backup Operators' -Defaults $script:Defaults | Should -BeTrue
    }
    It 'returns false for a custom account on SeBackupPrivilege' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeBackupPrivilege' -Account 'CORP\BackupSvc' -Defaults $script:Defaults | Should -BeFalse
    }
    It 'is case-insensitive' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeBackupPrivilege' -Account 'builtin\administrators' -Defaults $script:Defaults | Should -BeTrue
    }
    It 'returns false for a privilege not in the defaults list' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeUnknownPrivilege' -Account 'BUILTIN\Administrators' -Defaults $script:Defaults | Should -BeFalse
    }
    It 'returns false when privilege has empty defaults list (SeTcbPrivilege)' {
        Test-IsDefaultUserRightPrincipal -Privilege 'SeTcbPrivilege' -Account 'BUILTIN\Administrators' -Defaults $script:Defaults | Should -BeFalse
    }
}

