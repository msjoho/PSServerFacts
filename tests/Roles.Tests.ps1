. $PSScriptRoot/Bootstrap.ps1

Describe 'Get-ServerRoleFlag' {
    It 'returns all-false when nothing is collected' {
        $r = Get-ServerRoleFlag -Result ([pscustomobject]@{})
        $r.HasSqlServer   | Should -BeFalse
        $r.HasIis         | Should -BeFalse
        $r.HasFileShares  | Should -BeFalse
        $r.IsHyperVHost   | Should -BeFalse
        $r.IsDc           | Should -BeFalse
        $r.IsChefManaged  | Should -BeFalse
        $r.IsCriticalRole | Should -BeFalse
    }
    It 'detects HasSqlServer when SqlServer array has entries' {
        $r = Get-ServerRoleFlag -Result ([pscustomobject]@{ SqlServer = @([pscustomobject]@{InstanceName='MSSQLSERVER'}) })
        $r.HasSqlServer   | Should -BeTrue
        $r.IsCriticalRole | Should -BeTrue
    }
    It 'detects IsDc when AD-Domain-Services feature is installed' {
        $r = Get-ServerRoleFlag -Result ([pscustomobject]@{
            WindowsFeatures = @([pscustomobject]@{ Name='AD-Domain-Services'; Installed=$true })
        })
        $r.IsDc           | Should -BeTrue
        $r.IsCriticalRole | Should -BeTrue
    }
    It 'detects IsHyperVHost via feature OR vmms service' {
        $r1 = Get-ServerRoleFlag -Result ([pscustomobject]@{
            WindowsFeatures = @([pscustomobject]@{ Name='Hyper-V'; Installed=$true })
        })
        $r2 = Get-ServerRoleFlag -Result ([pscustomobject]@{
            Services = @([pscustomobject]@{ Name='vmms' })
        })
        $r1.IsHyperVHost | Should -BeTrue
        $r2.IsHyperVHost | Should -BeTrue
    }
    It 'detects IsChefManaged via Chef section' {
        $r = Get-ServerRoleFlag -Result ([pscustomobject]@{ Chef = [pscustomobject]@{ Installed=$true } })
        $r.IsChefManaged | Should -BeTrue
    }
    It 'IsCriticalRole is OR of SQL / DC / HyperV / (IIS with HTTPS bindings)' {
        $iisHttp  = Get-ServerRoleFlag -Result ([pscustomobject]@{ Iis = [pscustomobject]@{ Sites = @([pscustomobject]@{ Bindings = @([pscustomobject]@{ Protocol='http' }) }) } })
        $iisHttps = Get-ServerRoleFlag -Result ([pscustomobject]@{ Iis = [pscustomobject]@{ Sites = @([pscustomobject]@{ Bindings = @([pscustomobject]@{ Protocol='https' }) }) } })
        $iisHttp.HasIis           | Should -BeTrue
        $iisHttp.IsCriticalRole   | Should -BeFalse
        $iisHttps.IsCriticalRole  | Should -BeTrue
    }
}
