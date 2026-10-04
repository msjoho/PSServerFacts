. $PSScriptRoot/Bootstrap.ps1

Describe 'ConvertTo-AppliesToString' {
    It 'returns ThisFolderOnly for None/None' {
        ConvertTo-AppliesToString -InheritanceFlags 'None' -PropagationFlags 'None' | Should -Be 'ThisFolderOnly'
    }
    It 'returns ThisFolderSubfoldersAndFiles for ContainerInherit,ObjectInherit/None' {
        ConvertTo-AppliesToString -InheritanceFlags 'ContainerInherit, ObjectInherit' -PropagationFlags 'None' | Should -Be 'ThisFolderSubfoldersAndFiles'
    }
    It 'returns SubfoldersAndFilesOnly for ContainerInherit,ObjectInherit/InheritOnly' {
        ConvertTo-AppliesToString -InheritanceFlags 'ContainerInherit, ObjectInherit' -PropagationFlags 'InheritOnly' | Should -Be 'SubfoldersAndFilesOnly'
    }
    It 'returns SubfoldersOnly for ContainerInherit/InheritOnly' {
        ConvertTo-AppliesToString -InheritanceFlags 'ContainerInherit' -PropagationFlags 'InheritOnly' | Should -Be 'SubfoldersOnly'
    }
    It 'returns FilesOnly for ObjectInherit/InheritOnly' {
        ConvertTo-AppliesToString -InheritanceFlags 'ObjectInherit' -PropagationFlags 'InheritOnly' | Should -Be 'FilesOnly'
    }
    It 'returns ThisFolderAndSubfolders for ContainerInherit/None' {
        ConvertTo-AppliesToString -InheritanceFlags 'ContainerInherit' -PropagationFlags 'None' | Should -Be 'ThisFolderAndSubfolders'
    }
    It 'returns ThisFolderAndFiles for ObjectInherit/None' {
        ConvertTo-AppliesToString -InheritanceFlags 'ObjectInherit' -PropagationFlags 'None' | Should -Be 'ThisFolderAndFiles'
    }
}

Describe 'ConvertTo-NtfsPermissionEntry' {
    It 'normalizes a Get-Acl FileSystemAccessRule' {
        $ace = [pscustomobject]@{
            IdentityReference = 'CORP\Finance-RW'
            FileSystemRights  = 'Modify, Synchronize'
            AccessControlType = 'Allow'
            IsInherited       = $false
            InheritanceFlags  = 'ContainerInherit, ObjectInherit'
            PropagationFlags  = 'None'
        }
        $entry = ConvertTo-NtfsPermissionEntry -Ace $ace -Path 'D:\Shares\Finance' -SourceKind 'GetAcl'
        $entry.Path              | Should -Be 'D:\Shares\Finance'
        $entry.Account           | Should -Be 'CORP\Finance-RW'
        $entry.Rights            | Should -Be 'Modify, Synchronize'
        $entry.AccessControlType | Should -Be 'Allow'
        $entry.Inherited         | Should -BeFalse
        $entry.AppliesTo         | Should -Be 'ThisFolderSubfoldersAndFiles'
    }
    It 'normalizes a Get-NTFSAccess entry' {
        $ace = [pscustomobject]@{
            Account           = [pscustomobject]@{ AccountName = 'CORP\Finance-RW' }
            AccessRights      = 'Modify'
            AccessControlType = 'Allow'
            IsInherited       = $false
            InheritanceFlags  = 'ContainerInherit, ObjectInherit'
            PropagationFlags  = 'None'
            FullName          = 'D:\Shares\Finance'
        }
        $entry = ConvertTo-NtfsPermissionEntry -Ace $ace -SourceKind 'NTFSSecurity'
        $entry.Path     | Should -Be 'D:\Shares\Finance'
        $entry.Account  | Should -Be 'CORP\Finance-RW'
        $entry.Rights   | Should -Be 'Modify'
    }
}

Describe 'ConvertTo-ServiceAccountList' {
    It 'aggregates and deduplicates accounts across kinds' {
        $services = @(
            [pscustomobject]@{ Name='SvcA'; StartName='CORP\msvc_app' }
            [pscustomobject]@{ Name='SvcB'; StartName='LocalSystem' }
            [pscustomobject]@{ Name='SvcC'; StartName='NT AUTHORITY\NetworkService' }
        )
        $tasks = @(
            [pscustomobject]@{ TaskPath='\Backups\'; TaskName='Nightly'; RunAs='CORP\msvc_backup' }
            [pscustomobject]@{ TaskPath='\Apps\';    TaskName='Sync';    RunAs='CORP\msvc_app' }
        )
        $iis = [pscustomobject]@{
            Installed = $true
            AppPools  = @(
                [pscustomobject]@{ Name='Pool1'; IdentityType='SpecificUser'; Username='CORP\msvc_iis$' }
                [pscustomobject]@{ Name='Pool2'; IdentityType='ApplicationPoolIdentity'; Username=$null }
            )
        }
        $result = ConvertTo-ServiceAccountList -Services $services -ScheduledTasks $tasks -Iis $iis -Hostname 'SRV1'
        $result.Count | Should -Be 3
        ($result | Where-Object Account -eq 'CORP\msvc_app').UsedBy.Count | Should -Be 2
        ($result | Where-Object Account -eq 'CORP\msvc_iis$').Type        | Should -Be 'gMSA'
    }
    It 'excludes builtin and local accounts' {
        $services = @(
            [pscustomobject]@{ Name='X'; StartName='NT AUTHORITY\SYSTEM' }
            [pscustomobject]@{ Name='Y'; StartName='BUILTIN\Administrators' }
            [pscustomobject]@{ Name='Z'; StartName='SRV1\someone' }
            [pscustomobject]@{ Name='W'; StartName='LocalService' }
        )
        $result = ConvertTo-ServiceAccountList -Services $services -ScheduledTasks @() -Iis $null -Hostname 'SRV1'
        $result.Count | Should -Be 0
    }
    It 'handles UPN form' {
        $services = @([pscustomobject]@{ Name='X'; StartName='msvc@corp.contoso.com' })
        $result = ConvertTo-ServiceAccountList -Services $services -ScheduledTasks @() -Iis $null -Hostname 'SRV1'
        $result.Count | Should -Be 1
        $result[0].Account | Should -Be 'msvc@corp.contoso.com'
    }
}
