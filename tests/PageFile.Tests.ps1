. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemotePageFile' {
    BeforeAll { $script:RealSession = New-PSSession -UseWindowsPowerShell }
    AfterAll  { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns system-managed shape when AutomaticManagedPagefile is true' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                AutomaticManagedPagefile = $true
                PageFiles = @([pscustomobject]@{ Path='C:\pagefile.sys'; InitialMB=0; MaximumMB=0; AllocatedMB=2048; PeakMB=1156; CurrentMB=612 })
                CrashControl = [pscustomobject]@{ CrashDumpEnabled=7; DumpFile='%SystemRoot%\MEMORY.DMP'; DedicatedDumpFile=$null; Overwrite=$true; AutoReboot=$true }
            }
        }
        $r = Get-RemotePageFile -Session $script:RealSession
        $r.AutomaticManagedPagefile      | Should -BeTrue
        @($r.PageFiles).Count            | Should -Be 1
        $r.PageFiles[0].Path             | Should -Be 'C:\pagefile.sys'
        $r.CrashControl.CrashDumpEnabled | Should -Be 7
    }
    It 'returns fixed-size shape with InitialMB=MaximumMB' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                AutomaticManagedPagefile = $false
                PageFiles = @([pscustomobject]@{ Path='E:\pagefile.sys'; InitialMB=16384; MaximumMB=16384; AllocatedMB=16384; PeakMB=4096; CurrentMB=2048 })
                CrashControl = [pscustomobject]@{ CrashDumpEnabled=2; DumpFile='%SystemRoot%\MEMORY.DMP'; DedicatedDumpFile='F:\dump.dmp'; Overwrite=$true; AutoReboot=$true }
            }
        }
        $r = Get-RemotePageFile -Session $script:RealSession
        $r.AutomaticManagedPagefile       | Should -BeFalse
        $r.PageFiles[0].InitialMB         | Should -Be 16384
        $r.CrashControl.DedicatedDumpFile | Should -Be 'F:\dump.dmp'
    }
}
