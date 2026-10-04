function Get-RemoteHardware {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $cpus = @(Get-CimInstance Win32_Processor)
        $mem  = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
        [pscustomobject]@{
            CpuModel        = ($cpus | Select-Object -First 1).Name
            CpuSockets      = $cpus.Count
            CpuLogicalCores = ($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
            MemoryTotalGB   = [math]::Round($mem / 1GB, 2)
        }
    } | Select-Object CpuModel, CpuSockets, CpuLogicalCores, MemoryTotalGB
}
