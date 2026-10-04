. $PSScriptRoot/Bootstrap.ps1

Describe 'Resolve-DomainFqdn' {
    BeforeEach {
        $script:Cache = [hashtable]::Synchronized(@{})
    }
    It 'returns cached value without calling Get-AD*' {
        $Cache['CORP'] = 'corp.contoso.com'
        Mock -ModuleName 'PSServerFacts' Get-ADDomain { throw 'should not be called' }
        Resolve-DomainFqdn -NetbiosName 'CORP' -Cache $Cache | Should -Be 'corp.contoso.com'
    }
    It 'looks up via Get-ADDomain on cache miss and stores result' {
        Mock -ModuleName 'PSServerFacts' Get-ADDomain { [pscustomobject]@{ DNSRoot = 'corp.contoso.com' } } -ParameterFilter { $Identity -eq 'CORP' }
        Resolve-DomainFqdn -NetbiosName 'CORP' -Cache $Cache | Should -Be 'corp.contoso.com'
        $Cache['CORP'] | Should -Be 'corp.contoso.com'
    }
    It 'returns null and caches null on lookup failure' {
        Mock -ModuleName 'PSServerFacts' Get-ADDomain { throw 'unreachable' }
        Resolve-DomainFqdn -NetbiosName 'GHOST' -Cache $Cache | Should -BeNullOrEmpty
        $Cache.ContainsKey('GHOST') | Should -BeTrue
    }
    It 'is case-insensitive on the cache key' {
        $Cache['CORP'] = 'corp.contoso.com'
        Resolve-DomainFqdn -NetbiosName 'corp' -Cache $Cache | Should -Be 'corp.contoso.com'
    }
}

Describe 'Test-IsDefaultGroupSid' {
    It 'matches Domain Admins (RID 512)' {
        Test-IsDefaultGroupSid -Sid 'S-1-5-21-1-2-3-512' | Should -BeTrue
    }
    It 'matches Domain Users (RID 513) and Enterprise Admins (RID 519)' {
        Test-IsDefaultGroupSid -Sid 'S-1-5-21-1-2-3-513' | Should -BeTrue
        Test-IsDefaultGroupSid -Sid 'S-1-5-21-1-2-3-519' | Should -BeTrue
    }
    It 'rejects custom RIDs and short SIDs' {
        Test-IsDefaultGroupSid -Sid 'S-1-5-21-1-2-3-1129' | Should -BeFalse
        Test-IsDefaultGroupSid -Sid 'S-1-5-32-544'         | Should -BeFalse
        Test-IsDefaultGroupSid -Sid ''                     | Should -BeFalse
    }
}

Describe 'Resolve-AdPrincipal' {
    BeforeEach {
        $script:Cache = [hashtable]::Synchronized(@{ 'CORP' = 'corp.contoso.com' })
    }
    It 'resolves a direct user SID via objectSID filter' {
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            [pscustomobject]@{ ObjectClass='user'; SamAccountName='jdoe'; DistinguishedName='CN=John,DC=corp,DC=contoso,DC=com' }
        } -ParameterFilter { $Filter -and $Filter -match 'objectSID' }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-1-2-3-1001' -Account 'CORP\jdoe' -DomainCache $Cache
        $p.Type              | Should -Be 'User'
        $p.Account           | Should -Be 'CORP\jdoe'
        $p.Domain            | Should -Be 'corp.contoso.com'
        $p.SamAccountName    | Should -Be 'jdoe'
        $p.DistinguishedName | Should -Be 'CN=John,DC=corp,DC=contoso,DC=com'
        $p.ResolveError      | Should -BeNullOrEmpty
    }
    It 'returns Type=Group without flattening when an entry is a group' {
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            [pscustomobject]@{ ObjectClass='group'; SamAccountName='Tier1-Admins'; DistinguishedName='CN=Tier1,DC=corp,DC=contoso,DC=com' }
        } -ParameterFilter { $Filter -and $Filter -match 'objectSID' }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache
        $p.Type           | Should -Be 'Group'
        $p.SamAccountName | Should -Be 'Tier1-Admins'
        $p.PSObject.Properties['Members'] | Should -BeNullOrEmpty
    }
    It 'returns Unresolved with the AD error when lookup fails' {
        Mock -ModuleName 'PSServerFacts' Get-ADObject { throw 'directory unreachable' } -ParameterFilter { $Filter }
        Mock -ModuleName 'PSServerFacts' Get-ADObject { throw 'directory unreachable' } -ParameterFilter { $Identity }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-9-9-9-1' -Account 'CORP\foo' -DomainCache $Cache
        $p.Type         | Should -Be 'Unresolved'
        $p.ResolveError | Should -Match 'directory unreachable'
    }
    It 'returns LocalAccount when no domain mapping exists for the netbios prefix' {
        $emptyCache = [hashtable]::Synchronized(@{})
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-1111-2222-3333-500' -Account 'SUBDN261\Administrator' -DomainCache $emptyCache
        $p.Type           | Should -Be 'LocalAccount'
        $p.SamAccountName | Should -Be 'Administrator'
        $p.Domain         | Should -BeNullOrEmpty
    }
    It 'returns WellKnown for builtin SIDs without AD lookup' {
        Mock -ModuleName 'PSServerFacts' Get-ADObject { throw 'should not be called' }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-32-544' -Account 'BUILTIN\Administrators' -DomainCache $Cache
        $p.Type | Should -Be 'WellKnown'
    }
    It 'detects gMSA by trailing $' {
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            [pscustomobject]@{ ObjectClass='msDS-GroupManagedServiceAccount'; SamAccountName='msvc_app$'; DistinguishedName='CN=msvc_app,DC=corp,DC=contoso,DC=com' }
        } -ParameterFilter { $Filter -and $Filter -match 'objectSID' }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-1-2-3-3001' -Account 'CORP\msvc_app$' -DomainCache $Cache
        $p.Type | Should -Be 'gMSA'
    }
    It 'passes -Credential to Get-ADObject when CredentialMap has the principal''s domain' {
        $cred = New-Object pscredential('partner\svc-read',(ConvertTo-SecureString 'x' -AsPlainText -Force))
        $map  = @{ 'CORP.CONTOSO.COM' = $cred }
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            [pscustomobject]@{ ObjectClass='user'; SamAccountName='jdoe'; DistinguishedName='CN=John,DC=corp,DC=contoso,DC=com' }
        } -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
        $p = Resolve-AdPrincipal -Sid 'S-1-5-21-1-2-3-1001' -Account 'CORP\jdoe' -DomainCache $Cache -CredentialMap $map
        $p.Type           | Should -Be 'User'
        $p.SamAccountName | Should -Be 'jdoe'
        Should -Invoke -ModuleName 'PSServerFacts' Get-ADObject -Times 1 -Exactly -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
    }
    It 'does not pass -Credential for domains not in the CredentialMap' {
        $cred = New-Object pscredential('partner\svc-read',(ConvertTo-SecureString 'x' -AsPlainText -Force))
        $map  = @{ 'OTHER.EXAMPLE.NET' = $cred }
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            [pscustomobject]@{ ObjectClass='user'; SamAccountName='jdoe'; DistinguishedName='CN=John,DC=corp,DC=contoso,DC=com' }
        } -ParameterFilter { -not $Credential }
        Resolve-AdPrincipal -Sid 'S-1-5-21-1-2-3-1001' -Account 'CORP\jdoe' -DomainCache $Cache -CredentialMap $map | Out-Null
        Should -Invoke -ModuleName 'PSServerFacts' Get-ADObject -Times 1 -Exactly -ParameterFilter { -not $Credential }
    }
}

Describe 'Expand-AdGroupMember' {
    BeforeEach {
        $script:Cache = [hashtable]::Synchronized(@{ 'CORP' = 'corp.contoso.com' })
        # Group SID → DN lookup happens before Get-ADGroupMember; mock a default
        # mapping that returns a synthetic DN derived from the SID so each test
        # only needs to mock the membership side of things.
        Mock -ModuleName 'PSServerFacts' Get-ADObject {
            param($Filter, $Identity, $Server, $Properties)
            $sid = if ($Filter -match "'(?<s>S-[\d\-]+)'") { $matches['s'] } else { [string]$Identity }
            [pscustomobject]@{ DistinguishedName = "CN=GROUP-$sid,DC=corp,DC=contoso,DC=com" }
        }
    }
    It 'returns a flat list of users with the parent group in Path' {
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            @(
                [pscustomobject]@{ ObjectClass='user'; SamAccountName='alice'; Name='Alice Adams'; SID=[pscustomobject]@{Value='S-1-5-21-x-1'}; DistinguishedName='CN=Alice,DC=corp,DC=contoso,DC=com' }
                [pscustomobject]@{ ObjectClass='user'; SamAccountName='bob';   Name='Bob Brown';   SID=[pscustomobject]@{Value='S-1-5-21-x-2'}; DistinguishedName='CN=Bob,DC=corp,DC=contoso,DC=com' }
            )
        }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache)
        $r.Count                | Should -Be 2
        $r[0].SamAccountName    | Should -Be 'alice'
        $r[0].Name              | Should -Be 'Alice Adams'
        $r[0].Type              | Should -Be 'User'
        $r[0].Account           | Should -Be 'CORP\alice'
        $r[0].Domain            | Should -Be 'corp.contoso.com'
        $r[0].Path              | Should -Be @('CORP\Tier1-Admins')
    }
    It 'walks in-forest nested groups manually so every level shows in Path' {
        # The big regression behind the rewrite: -Recursive used to flatten
        # in-forest nesting and we lost the intermediate group(s). Manual
        # recursion must emit each level — group row + leaf row — and the
        # leaf's Path must include every intermediate group.
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            param($Identity, $Server, [pscredential]$Credential)
            if ([string]$Identity -match 'S-1-5-21-1-2-3-3001') {
                @( [pscustomobject]@{ ObjectClass='user'; SamAccountName='deepAlice'; Name='Deep Alice'; SID=[pscustomobject]@{Value='S-1-5-21-x-99'}; DistinguishedName='CN=Deep Alice,DC=corp,DC=contoso,DC=com' } )
            } else {
                @( [pscustomobject]@{ ObjectClass='group'; SamAccountName='Mid-Group'; Name='Mid Group'; SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-3001'}; DistinguishedName='CN=Mid-Group,DC=corp,DC=contoso,DC=com' } )
            }
        }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache)
        ($r | Where-Object SamAccountName -eq 'Mid-Group').Type | Should -Be 'Group'
        ($r | Where-Object SamAccountName -eq 'Mid-Group').Path | Should -Be @('CORP\Tier1-Admins')
        ($r | Where-Object SamAccountName -eq 'deepAlice').Path | Should -Be @('CORP\Tier1-Admins','CORP\Mid-Group')
    }
    It 'derives Domain from the member DN and attributes Account to the correct netbios when known' {
        $Cache['AXUSR'] = 'axusr.net'
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            @( [pscustomobject]@{ ObjectClass='user'; SamAccountName='dt.user'; Name='DT User'; SID=[pscustomobject]@{Value='S-1-5-21-9-9-9-1'}; DistinguishedName='CN=DT User,OU=DAdmins,DC=axusr,DC=net' } )
        }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache)
        # Cross-trust member: DN says DC=axusr,DC=net → home domain is AXUSR
        $r[0].Domain  | Should -Be 'axusr.net'
        $r[0].Account | Should -Be 'AXUSR\dt.user'
    }
    It 'recurses through cross-trust nested groups, extending Path' {
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            param($Identity, $Server, [switch]$Recursive)
            if ([string]$Identity -match 'S-1-5-21-2-2-2-3001') {
                @( [pscustomobject]@{ ObjectClass='user'; SamAccountName='trustedAlice'; Name='Trusted Alice'; SID=[pscustomobject]@{Value='S-1-5-21-2-2-2-1001'}; DistinguishedName='CN=Alice,DC=trusted,DC=example,DC=com' } )
            } else {
                @(
                    [pscustomobject]@{ ObjectClass='user';  SamAccountName='alice'; Name='Alice'; SID=[pscustomobject]@{Value='S-1-5-21-x-1'}; DistinguishedName='CN=Alice,DC=corp,DC=contoso,DC=com' }
                    [pscustomobject]@{ ObjectClass='group'; SamAccountName='Trusted-Admins'; Name='Trusted Admins'; SID=[pscustomobject]@{Value='S-1-5-21-2-2-2-3001'}; DistinguishedName='CN=Trusted-Admins,DC=trusted,DC=example,DC=com' }
                )
            }
        }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache)
        ($r | Where-Object SamAccountName -eq 'alice').Path        | Should -Be @('CORP\Tier1-Admins')
        $trusted = $r | Where-Object SamAccountName -eq 'trustedAlice'
        $trusted | Should -Not -BeNullOrEmpty
        $trusted.Path | Should -Be @('CORP\Tier1-Admins','CORP\Trusted-Admins')
    }
    It 'with -SkipDefaultGroupExpansion stops at default group SIDs but still emits the group entry' {
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            param($Identity, $Server, [switch]$Recursive)
            if ([string]$Identity -match 'S-1-5-21-1-2-3-512') {
                throw 'should not be called when -SkipDefaultGroupExpansion is set'
            }
            @(
                [pscustomobject]@{ ObjectClass='user';  SamAccountName='alice'; Name='Alice'; SID=[pscustomobject]@{Value='S-1-5-21-x-1'}; DistinguishedName='CN=Alice,DC=corp,DC=contoso,DC=com' }
                [pscustomobject]@{ ObjectClass='group'; SamAccountName='Domain Admins'; Name='Domain Admins'; SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-512'}; DistinguishedName='CN=Domain Admins,DC=corp,DC=contoso,DC=com' }
            )
        }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache -SkipDefaultGroupExpansion)
        $defGroup = $r | Where-Object SamAccountName -eq 'Domain Admins'
        $defGroup.Skipped | Should -BeTrue
        $defGroup.Type    | Should -Be 'Group'
    }
    It 'returns empty array when AD lookup fails' {
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember { throw 'unreachable' }
        @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache).Count | Should -Be 0
    }
    It 'passes -Credential to both Get-ADObject and Get-ADGroupMember when CredentialMap has the group''s domain' {
        $cred = New-Object pscredential('partner\svc-read',(ConvertTo-SecureString 'x' -AsPlainText -Force))
        $map  = @{ 'CORP.CONTOSO.COM' = $cred }
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            @( [pscustomobject]@{ ObjectClass='user'; SamAccountName='alice'; Name='Alice'; SID=[pscustomobject]@{Value='S-1-5-21-x-1'}; DistinguishedName='CN=Alice,DC=corp,DC=contoso,DC=com' } )
        } -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache -CredentialMap $map)
        $r.Count | Should -Be 1
        $r[0].SamAccountName | Should -Be 'alice'
        Should -Invoke -ModuleName 'PSServerFacts' Get-ADObject      -Times 1 -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
        Should -Invoke -ModuleName 'PSServerFacts' Get-ADGroupMember -Times 1 -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
    }
    It 'forwards CredentialMap to recursive calls so cross-trust nested groups get the credential too' {
        $cred = New-Object pscredential('partner\svc-read',(ConvertTo-SecureString 'x' -AsPlainText -Force))
        $map  = @{
            'CORP.CONTOSO.COM'    = $cred
            'TRUSTED.EXAMPLE.COM' = $cred
        }
        # Seed the partner domain into the cache so the recursion can resolve it.
        $Cache['TRUSTED'] = 'trusted.example.com'
        Mock -ModuleName 'PSServerFacts' Get-ADGroupMember {
            param($Identity, $Server, [switch]$Recursive, [pscredential]$Credential)
            if ([string]$Identity -match 'S-1-5-21-2-2-2-3001') {
                @( [pscustomobject]@{ ObjectClass='user'; SamAccountName='trustedAlice'; Name='Trusted Alice'; SID=[pscustomobject]@{Value='S-1-5-21-2-2-2-1001'}; DistinguishedName='CN=Alice,DC=trusted,DC=example,DC=com' } )
            } else {
                @( [pscustomobject]@{ ObjectClass='group'; SamAccountName='Trusted-Admins'; Name='Trusted Admins'; SID=[pscustomobject]@{Value='S-1-5-21-2-2-2-3001'}; DistinguishedName='CN=Trusted-Admins,DC=trusted,DC=example,DC=com' } )
            }
        } -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
        $r = @(Expand-AdGroupMember -Sid 'S-1-5-21-1-2-3-2001' -Account 'CORP\Tier1-Admins' -DomainCache $Cache -CredentialMap $map)
        ($r | Where-Object SamAccountName -eq 'trustedAlice') | Should -Not -BeNullOrEmpty
        # Both the outer (CORP) and recursive (TRUSTED) calls must carry the credential.
        Should -Invoke -ModuleName 'PSServerFacts' Get-ADGroupMember -Times 2 -ParameterFilter { $Credential -and $Credential.UserName -eq 'partner\svc-read' }
    }
}

