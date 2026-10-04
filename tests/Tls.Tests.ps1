. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteTls' {
    BeforeAll { $script:RealSession = New-PSSession -UseWindowsPowerShell }
    AfterAll  { Remove-PSSession -Session $script:RealSession -ErrorAction SilentlyContinue }

    It 'returns 12 protocol/side combos (SSL2/SSL3/TLS10/TLS11/TLS12/TLS13 × Client/Server)' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Protocols = @(
                    foreach ($name in 'SSL 2.0','SSL 3.0','TLS 1.0','TLS 1.1','TLS 1.2','TLS 1.3') {
                        foreach ($side in 'Client','Server') {
                            [pscustomobject]@{ Name=$name; Side=$side; Enabled=$false; DisabledByDefault=$true }
                        }
                    }
                )
            }
        }
        $r = Get-RemoteTls -Session $script:RealSession
        @($r.Protocols).Count | Should -Be 12
    }
    It 'flags TLS 1.0 Server as enabled when registry says so' {
        Mock -ModuleName 'PSServerFacts' Invoke-Command {
            [pscustomobject]@{
                Protocols = @(
                    [pscustomobject]@{ Name='TLS 1.0'; Side='Server'; Enabled=$true;  DisabledByDefault=$false }
                    [pscustomobject]@{ Name='TLS 1.0'; Side='Client'; Enabled=$false; DisabledByDefault=$true  }
                )
            }
        }
        $r = Get-RemoteTls -Session $script:RealSession
        ($r.Protocols | Where-Object { $_.Name -eq 'TLS 1.0' -and $_.Side -eq 'Server' }).Enabled | Should -BeTrue
    }
}
