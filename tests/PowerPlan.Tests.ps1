. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemotePowerPlan' {
    BeforeAll { $script:RealSession = New-PSSession -UseWindowsPowerShell }
    AfterAll  { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns active scheme and list of available schemes' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                ActiveSchemeGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
                ActiveSchemeName = 'High Performance'
                AvailableSchemes = @(
                    [pscustomobject]@{ Guid='381b4222-f694-41f0-9685-ff5bb260df2e'; Name='Balanced';         IsActive=$false }
                    [pscustomobject]@{ Guid='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Name='High Performance'; IsActive=$true  }
                )
            }
        }
        $r = Get-RemotePowerPlan -Session $script:RealSession
        $r.ActiveSchemeName          | Should -Be 'High Performance'
        @($r.AvailableSchemes).Count | Should -Be 2
    }
}
