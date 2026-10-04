. $PSScriptRoot/Bootstrap.ps1

Describe 'Data files' {
    It 'DefaultServices.psd1 loads and has KnownDefaults and KnownCustomFalsePositives keys' {
        $data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultServices.psd1"
        $data.Keys | Should -Contain 'KnownDefaults'
        $data.Keys | Should -Contain 'KnownCustomFalsePositives'
        ,$data.KnownDefaults              | Should -BeOfType [array]
        ,$data.KnownCustomFalsePositives  | Should -BeOfType [array]
    }
    It 'DefaultShares.psd1 loads and has Names array' {
        $data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultShares.psd1"
        ,$data.Names | Should -BeOfType [array]
        $data.Names | Should -Contain 'IPC$'
    }
    It 'DefaultTaskPaths.psd1 loads and has Patterns array' {
        $data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultTaskPaths.psd1"
        $data.Patterns | Should -Contain '\Microsoft\*'
    }
    It 'DefaultCertIssuers.psd1 loads and has Issuers array' {
        $data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultCertIssuers.psd1"
        ,$data.Issuers | Should -BeOfType [array]
    }
    It 'DefaultFirewallGroupPrefixes.psd1 loads and has Prefixes array' {
        $data = Import-PowerShellDataFile -Path "$RepoRoot/PSServerFacts/data/DefaultFirewallGroupPrefixes.psd1"
        $data.Prefixes | Should -Contain '@FirewallAPI.dll'
    }
}

Describe 'Format-TriggerSummary' {
    It 'formats a daily trigger' {
        $t = [pscustomobject]@{ CimClass = @{ CimClassName = 'MSFT_TaskDailyTrigger' }; StartBoundary = '2026-04-30T02:00:00'; DaysInterval = 1 }
        Format-TriggerSummary -Trigger $t | Should -Be 'Daily at 02:00'
    }
    It 'formats a weekly trigger with days bitmask' {
        # Mon=2, Wed=8 -> 10
        $t = [pscustomobject]@{ CimClass = @{ CimClassName = 'MSFT_TaskWeeklyTrigger' }; StartBoundary = '2026-04-30T06:30:00'; DaysOfWeek = 10; WeeksInterval = 1 }
        Format-TriggerSummary -Trigger $t | Should -Be 'Weekly on Mon, Wed at 06:30'
    }
    It 'formats a boot trigger' {
        $t = [pscustomobject]@{ CimClass = @{ CimClassName = 'MSFT_TaskBootTrigger' } }
        Format-TriggerSummary -Trigger $t | Should -Be 'At system startup'
    }
    It 'formats a logon trigger' {
        $t = [pscustomobject]@{ CimClass = @{ CimClassName = 'MSFT_TaskLogonTrigger' }; UserId = 'DOMAIN\u' }
        Format-TriggerSummary -Trigger $t | Should -Be 'At logon of DOMAIN\u'
    }
    It 'falls back to class name for unknown trigger types' {
        $t = [pscustomobject]@{ CimClass = @{ CimClassName = 'MSFT_TaskWnfStateChangeTrigger' } }
        Format-TriggerSummary -Trigger $t | Should -Be 'MSFT_TaskWnfStateChangeTrigger'
    }
}

Describe 'Test-JumphostPrerequisite' {
    It 'throws when PS major < 7' {
        Mock -ModuleName 'PSServerFacts' Get-Module { @() } -ParameterFilter { $ListAvailable }
        { Test-JumphostPrerequisite -PSVersion ([version]'5.1.0.0') } | Should -Throw -ExpectedMessage '*PowerShell 7*'
    }
    It 'throws when ActiveDirectory module missing' {
        Mock -ModuleName 'PSServerFacts' Get-Module { @() } -ParameterFilter { $ListAvailable -and $Name -eq 'ActiveDirectory' }
        Mock -ModuleName 'PSServerFacts' Get-Module { [pscustomobject]@{ Name = 'NTFSSecurity' } } -ParameterFilter { $ListAvailable -and $Name -eq 'NTFSSecurity' }
        Mock -ModuleName 'PSServerFacts' Import-Module {}
        { Test-JumphostPrerequisite -SkipPSVersionCheck } | Should -Throw -ExpectedMessage '*ActiveDirectory*'
    }
}

Describe 'New-RunFolder' {
    It 'creates a timestamped folder under root' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        try {
            $folder = New-RunFolder -Root $tmp
            Test-Path $folder | Should -BeTrue
            (Split-Path $folder -Leaf) | Should -Match '^\d{4}-\d{2}-\d{2}_\d{6}_\d{3}$'
        } finally { Remove-Item -Recurse -Force -ErrorAction Ignore $tmp }
    }
}

Describe 'Invoke-WithSession' {
    It 'invokes the script block with a session and removes the session afterward' {
        Mock -ModuleName 'PSServerFacts' New-PSSession {
            [pscustomobject]@{ Id = 1; ComputerName = 'fake' }
        }
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}

        $r = Invoke-WithSession -ComputerName 'fake' -ScriptBlock { param($s) "ran-on-$($s.ComputerName)" }
        $r | Should -Be 'ran-on-fake'

        Should -Invoke -ModuleName 'PSServerFacts' Remove-PSSession -Times 1 -Exactly
    }
    It 'still removes session if script throws' {
        Mock -ModuleName 'PSServerFacts' New-PSSession {
            [pscustomobject]@{ Id = 1; ComputerName = 'fake' }
        }
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}

        { Invoke-WithSession -ComputerName 'fake' -ScriptBlock { throw 'boom' } } | Should -Throw 'boom'
        Should -Invoke -ModuleName 'PSServerFacts' Remove-PSSession -Times 1 -Exactly
    }
    It 'forwards Credential to New-PSSession when provided' {
        $cred = [pscredential]::new('user',(ConvertTo-SecureString 'p' -AsPlainText -Force))
        Mock -ModuleName 'PSServerFacts' New-PSSession {
            [pscustomobject]@{ Id = 1; ComputerName = 'fake' }
        }
        Mock -ModuleName 'PSServerFacts' Remove-PSSession {}

        Invoke-WithSession -ComputerName 'fake' -Credential $cred -ScriptBlock { param($s) 'ok' } | Out-Null

        Should -Invoke -ModuleName 'PSServerFacts' New-PSSession -ParameterFilter {
            $Credential -and $Credential.UserName -eq 'user'
        } -Times 1 -Exactly
    }
}


