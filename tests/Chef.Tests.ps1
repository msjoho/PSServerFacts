. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-RemoteChef — client.rb parser' {
    BeforeAll {
        $script:fixtureRb = Get-Content -Raw "$RepoRoot/tests/fixtures/chef-client.rb"
    }

    It 'extracts node_name, chef_server_url, environment, validation_client_name' {
        $r = ConvertFrom-ChefClientRb -Content $fixtureRb
        $r.NodeName         | Should -Be 'srv01.prod.example.com'
        $r.ChefServerUrl    | Should -Be 'https://chef.example.com/organizations/myorg'
        $r.Environment      | Should -Be 'prod'
        $r.ValidationClient | Should -Be 'myorg-validator'
    }

    It 'returns null fields for missing keys' {
        $r = ConvertFrom-ChefClientRb -Content "node_name 'foo'"
        $r.NodeName      | Should -Be 'foo'
        $r.ChefServerUrl | Should -BeNullOrEmpty
    }

    It 'ignores comments and blank lines' {
        $r = ConvertFrom-ChefClientRb -Content @"
# this is a comment
node_name 'bar'

  environment   "test"
"@
        $r.NodeName    | Should -Be 'bar'
        $r.Environment | Should -Be 'test'
    }
}

Describe 'Get-RemoteChef — last-run extractor' {
    BeforeAll {
        $script:fixturePath = "$RepoRoot/tests/fixtures/chef-last-run-report.json"
    }

    It 'returns RunList verbatim' {
        $r = ConvertFrom-ChefLastRunReport -Path $fixturePath
        $r.RunList | Should -Be @('role[base]','role[appserver]','recipe[mycookbook::install]')
    }

    It 'returns AttributeKeys top-level only (no values)' {
        $r = ConvertFrom-ChefLastRunReport -Path $fixturePath
        $r.AttributeKeys.default   | Should -Be @('apache','mysql')
        $r.AttributeKeys.normal    | Should -Be @('mycookbook')
        @($r.AttributeKeys.override).Count | Should -Be 0
        @($r.AttributeKeys.override) -contains $null | Should -Be $false
        $r.AttributeKeys.automatic | Should -Contain 'fqdn'
    }

    It 'extracts LastSuccessfulRunUtc from end_time' {
        $r = ConvertFrom-ChefLastRunReport -Path $fixturePath
        $r.LastSuccessfulRunUtc | Should -Be '2026-05-04T03:14:22Z'
    }

    It 'returns null on missing path' {
        ConvertFrom-ChefLastRunReport -Path 'C:\does\not\exist.json' | Should -BeNullOrEmpty
    }
}

Describe 'Get-RemoteChef — client.log run-list parser' {
    It 'returns empty array on empty input' {
        @(ConvertFrom-ChefClientLog -Content '').Count | Should -Be 0
    }
    It 'extracts a recipe-only run list' {
        $log = @"
[2026-05-08T03:14:01+00:00] INFO: *** Chef Infra Client 17.10.0 ***
[2026-05-08T03:14:02+00:00] INFO: Run List is [recipe[base::default], recipe[ntp]]
[2026-05-08T03:14:02+00:00] INFO: Starting Chef Infra Client Run
"@
        $r = ConvertFrom-ChefClientLog -Content $log
        $r | Should -Be @('recipe[base::default]','recipe[ntp]')
    }
    It 'extracts a mixed recipe + role run list' {
        $log = "[2026-05-08T03:14:02+00:00] INFO: Run List is [recipe[base::default], role[appserver], recipe[mycookbook::install]]`n"
        $r = ConvertFrom-ChefClientLog -Content $log
        $r | Should -Be @('recipe[base::default]','role[appserver]','recipe[mycookbook::install]')
    }
    It 'returns the most recent run list when the log spans multiple runs' {
        $log = @"
[2026-05-07T03:00:00+00:00] INFO: Run List is [recipe[old::cookbook]]
[2026-05-08T03:00:00+00:00] INFO: Run List is [recipe[new::cookbook], role[web]]
"@
        $r = ConvertFrom-ChefClientLog -Content $log
        $r | Should -Be @('recipe[new::cookbook]','role[web]')
    }
    It 'returns empty array when no run-list line is present' {
        $log = "[2026-05-08T03:14:01+00:00] INFO: chef ran nothing of interest`n"
        @(ConvertFrom-ChefClientLog -Content $log).Count | Should -Be 0
    }
}

Describe 'Get-RemoteChef — detection (mocked session)' {
    It 'returns null when neither registry nor file present' {
        $session = New-PSSession -UseWindowsPowerShell
        try {
            Mock -ModuleName 'PSServerFacts' Invoke-Command { return $null } -ParameterFilter { $true }
            (Get-RemoteChef -Session $session) | Should -BeNullOrEmpty
        } finally { Remove-PSSession $session }
    }
}

