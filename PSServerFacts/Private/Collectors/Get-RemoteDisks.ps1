function Get-RemoteDisks {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
            $totalGB = [math]::Round($_.Size / 1GB, 1)
            $freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
            $usedPct = if ($_.Size) { [math]::Round((1 - ($_.FreeSpace / $_.Size)) * 100, 1) } else { 0 }
            [pscustomobject]@{
                Drive=$_.DeviceID; Label=$_.VolumeName; FileSystem=$_.FileSystem
                TotalGB=$totalGB; FreeGB=$freeGB; UsedPct=$usedPct
            }
        }
    } | Select-Object Drive, Label, FileSystem, TotalGB, FreeGB, UsedPct
}
