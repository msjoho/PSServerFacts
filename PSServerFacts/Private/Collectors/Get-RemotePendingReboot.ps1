function Get-RemotePendingReboot {
    # All five flags are registry/WMI reads on the target. Any one true means
    # the host has a pending reboot — advisor escalates to Note (universal).
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    $raw = Invoke-Command -Session $Session -ScriptBlock {
        $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $wu  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $pfr = $false
        try {
            $vals = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop).PendingFileRenameOperations
            $pfr = ($vals -is [string[]]) -and ($vals.Count -gt 0)
        } catch { }
        $cnc = $false
        try {
            $active = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -ErrorAction Stop).ComputerName
            $next   = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'       -ErrorAction Stop).ComputerName
            $cnc    = $active -ne $next
        } catch { }
        $ccm = $false
        try {
            $r = Invoke-CimMethod -Namespace 'ROOT\ccm\ClientSDK' -ClassName 'CCM_ClientUtilities' -MethodName 'DetermineIfRebootPending' -ErrorAction Stop
            $ccm = [bool]$r.RebootPending
        } catch { }
        [pscustomobject]@{
            ComponentBasedServicing = $cbs
            WindowsUpdate           = $wu
            PendingFileRenameOps    = $pfr
            ComputerNameChange      = $cnc
            CcmClientSDK            = $ccm
        }
    }

    $any = $raw.ComponentBasedServicing -or $raw.WindowsUpdate -or $raw.PendingFileRenameOps -or $raw.ComputerNameChange -or $raw.CcmClientSDK
    [pscustomobject]@{
        ComponentBasedServicing = $raw.ComponentBasedServicing
        WindowsUpdate           = $raw.WindowsUpdate
        PendingFileRenameOps    = $raw.PendingFileRenameOps
        ComputerNameChange      = $raw.ComputerNameChange
        CcmClientSDK            = $raw.CcmClientSDK
        Any                     = $any
    }
}
