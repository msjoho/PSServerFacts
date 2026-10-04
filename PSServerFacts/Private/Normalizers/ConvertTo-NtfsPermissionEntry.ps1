function ConvertTo-NtfsPermissionEntry {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Ace,
        [string]$Path,
        [Parameter(Mandatory)][ValidateSet('GetAcl','NTFSSecurity')][string]$SourceKind
    )
    if ($SourceKind -eq 'GetAcl') {
        $account = [string]$Ace.IdentityReference
        $rights  = [string]$Ace.FileSystemRights
        $resolvedPath = $Path
    } else {
        $account = if ($Ace.Account -is [string]) { $Ace.Account } else { [string]$Ace.Account.AccountName }
        $rights  = [string]$Ace.AccessRights
        $resolvedPath = if ($Path) { $Path } else { [string]$Ace.FullName }
    }

    [pscustomobject]@{
        Path              = $resolvedPath
        Account           = $account
        Rights            = $rights
        AppliesTo         = ConvertTo-AppliesToString -InheritanceFlags ([string]$Ace.InheritanceFlags) -PropagationFlags ([string]$Ace.PropagationFlags)
        Inherited         = [bool]$Ace.IsInherited
        AccessControlType = [string]$Ace.AccessControlType
    }
}
