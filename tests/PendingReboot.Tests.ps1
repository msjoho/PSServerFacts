. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemotePendingReboot' {
    BeforeAll {
        $script:RealSession = New-PSSession -UseWindowsPowerShell
    }
    AfterAll { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns all-false when no flags are set' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                ComponentBasedServicing=$false; WindowsUpdate=$false
                PendingFileRenameOps=$false; ComputerNameChange=$false
                CcmClientSDK=$false
            }
        }
        $r = Get-RemotePendingReboot -Session $script:RealSession
        $r.Any                     | Should -BeFalse
        $r.ComponentBasedServicing | Should -BeFalse
    }
    It 'sets Any when CBS or WindowsUpdate is true' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                ComponentBasedServicing=$true; WindowsUpdate=$false
                PendingFileRenameOps=$false; ComputerNameChange=$false
                CcmClientSDK=$false
            }
        }
        $r = Get-RemotePendingReboot -Session $script:RealSession
        $r.ComponentBasedServicing | Should -BeTrue
        $r.Any                     | Should -BeTrue
    }
    It 'sets Any when PendingFileRenameOps is true' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                ComponentBasedServicing=$false; WindowsUpdate=$false
                PendingFileRenameOps=$true; ComputerNameChange=$false
                CcmClientSDK=$false
            }
        }
        (Get-RemotePendingReboot -Session $script:RealSession).Any | Should -BeTrue
    }
}
