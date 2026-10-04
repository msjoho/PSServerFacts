function Get-RemotePageFile {
    # Combines Win32_ComputerSystem.AutomaticManagedPagefile, Win32_PageFileSetting
    # (configured), Win32_PageFileUsage (runtime), HKLM:\…\CrashControl.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $auto = [bool](Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile
        $cfg  = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue)
        $use  = @(Get-CimInstance Win32_PageFileUsage   -ErrorAction SilentlyContinue)
        $pfs = @(foreach ($u in $use) {
            $c = $cfg | Where-Object { $_.Name -eq $u.Name } | Select-Object -First 1
            [pscustomobject]@{
                Path        = $u.Name
                InitialMB   = if ($c) { [int]$c.InitialSize } else { 0 }
                MaximumMB   = if ($c) { [int]$c.MaximumSize } else { 0 }
                AllocatedMB = [int]$u.AllocatedBaseSize
                PeakMB      = [int]$u.PeakUsage
                CurrentMB   = [int]$u.CurrentUsage
            }
        })
        $cc = $null
        try {
            $reg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -ErrorAction Stop
            $cc = [pscustomobject]@{
                CrashDumpEnabled  = [int]$reg.CrashDumpEnabled
                DumpFile          = [string]$reg.DumpFile
                DedicatedDumpFile = $reg.PSObject.Properties['DedicatedDumpFile'].Value
                Overwrite         = [bool]$reg.Overwrite
                AutoReboot        = [bool]$reg.AutoReboot
            }
        } catch { }
        [pscustomobject]@{
            AutomaticManagedPagefile = $auto
            PageFiles    = $pfs
            CrashControl = $cc
        }
    }
}
