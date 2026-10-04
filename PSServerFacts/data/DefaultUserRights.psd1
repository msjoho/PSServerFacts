@{
    # Per-privilege default principals on a vanilla Windows Server (2019/2022).
    # The orchestrator filters URA to only show entries NOT in these defaults,
    # unless -IncludeAllUserRights is set.
    Defaults = @{
        SeTcbPrivilege                = @()  # No defaults — only LocalSystem implicitly.
        SeBackupPrivilege             = @('BUILTIN\Administrators','BUILTIN\Backup Operators')
        SeRestorePrivilege            = @('BUILTIN\Administrators','BUILTIN\Backup Operators')
        SeDebugPrivilege              = @('BUILTIN\Administrators')
        SeServiceLogonRight           = @('NT SERVICE\ALL SERVICES')
        SeBatchLogonRight             = @('BUILTIN\Administrators','BUILTIN\Backup Operators','BUILTIN\Performance Log Users','BUILTIN\IIS_IUSRS')
        SeInteractiveLogonRight       = @('BUILTIN\Administrators','BUILTIN\Users','BUILTIN\Backup Operators')
        SeRemoteInteractiveLogonRight = @('BUILTIN\Administrators','BUILTIN\Remote Desktop Users')
        SeDenyInteractiveLogonRight   = @()
        SeDenyNetworkLogonRight       = @()
        SeLoadDriverPrivilege         = @('BUILTIN\Administrators','BUILTIN\Print Operators')
        SeTakeOwnershipPrivilege      = @('BUILTIN\Administrators')
        SeAssignPrimaryTokenPrivilege = @('NT AUTHORITY\LOCAL SERVICE','NT AUTHORITY\NETWORK SERVICE')
        SeImpersonatePrivilege        = @('NT AUTHORITY\LOCAL SERVICE','NT AUTHORITY\NETWORK SERVICE','NT AUTHORITY\SERVICE','BUILTIN\Administrators')
        SeShutdownPrivilege           = @('BUILTIN\Administrators','BUILTIN\Backup Operators')
    }
}
