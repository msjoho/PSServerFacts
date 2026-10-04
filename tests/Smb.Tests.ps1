. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteSmb' {
    BeforeAll { $script:RealSession = New-PSSession -UseWindowsPowerShell }
    AfterAll  { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns hardened defaults shape' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Smb1Enabled=$false; Smb2Enabled=$true; SigningRequired=$true; SigningEnabled=$true
                EncryptData=$false; RejectUnencryptedAccess=$false; AuditSmb1Access=$true; Smb1ClientInstalled=$false
            }
        }
        $r = Get-RemoteSmb -Session $script:RealSession
        $r.Smb1Enabled     | Should -BeFalse
        $r.SigningRequired | Should -BeTrue
    }
    It 'reports Smb1Enabled true when registry/config says so' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Smb1Enabled=$true; Smb2Enabled=$true; SigningRequired=$false; SigningEnabled=$true
                EncryptData=$false; RejectUnencryptedAccess=$false; AuditSmb1Access=$false; Smb1ClientInstalled=$true
            }
        }
        (Get-RemoteSmb -Session $script:RealSession).Smb1Enabled | Should -BeTrue
    }
}
