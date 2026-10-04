. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteDefender' {
    BeforeAll { $script:RealSession = New-PSSession -UseWindowsPowerShell }
    AfterAll  { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns engine status + exclusions' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Engine = [pscustomobject]@{
                    AntivirusEnabled=$true; RealTimeProtectionEnabled=$true; TamperProtected=$true; AMServiceEnabled=$true
                    AntivirusSignatureLastUpdatedUtc='2026-05-11T03:14:00Z'; AntivirusSignatureAgeDays=1
                }
                Exclusions = [pscustomobject]@{
                    Paths=@('D:\SQLData','D:\SQLLog'); Extensions=@('.mdf','.ldf','.bak'); Processes=@('sqlservr.exe')
                }
            }
        }
        $r = Get-RemoteDefender -Session $script:RealSession
        $r.Engine.RealTimeProtectionEnabled | Should -BeTrue
        @($r.Exclusions.Paths).Count        | Should -Be 2
    }
    It 'reports RT disabled when off' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Engine = [pscustomobject]@{
                    AntivirusEnabled=$true; RealTimeProtectionEnabled=$false; TamperProtected=$true; AMServiceEnabled=$true
                    AntivirusSignatureLastUpdatedUtc=$null; AntivirusSignatureAgeDays=999
                }
                Exclusions = [pscustomobject]@{ Paths=@(); Extensions=@(); Processes=@() }
            }
        }
        (Get-RemoteDefender -Session $script:RealSession).Engine.RealTimeProtectionEnabled | Should -BeFalse
    }
}
