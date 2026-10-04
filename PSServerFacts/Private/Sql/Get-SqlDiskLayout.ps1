function Get-SqlDiskLayout {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Databases,
        [AllowNull()][AllowEmptyCollection()][object[]]$Disks
    )

    $rolesByDrive = @{}
    foreach ($db in $Databases) {
        $isTemp = ($db.Name -eq 'tempdb')
        $isSys  = [bool]$db.IsSystem
        foreach ($f in @($db.Files)) {
            $drive = ([string]$f.PhysicalPath).Substring(0,2).ToUpperInvariant()
            $role = if ($isTemp) {
                if ($f.Type -eq 'Log') { 'TempDbLog' } else { 'TempDbData' }
            } elseif ($isSys) {
                if ($f.Type -eq 'Log') { 'SystemLog' } else { 'SystemData' }
            } else {
                if ($f.Type -eq 'Log') { 'UserLog' } else { 'UserData' }
            }
            if (-not $rolesByDrive.ContainsKey($drive)) {
                $rolesByDrive[$drive] = New-Object System.Collections.Generic.HashSet[string]
            }
            $null = $rolesByDrive[$drive].Add($role)
        }
    }

    foreach ($drive in ($rolesByDrive.Keys | Sort-Object)) {
        $diskRow = $Disks | Where-Object { ([string]$_.Drive).ToUpperInvariant() -eq $drive } | Select-Object -First 1
        [pscustomobject]@{
            Drive    = $drive
            Roles    = @($rolesByDrive[$drive] | Sort-Object)
            TotalGB  = if ($diskRow) { [double]$diskRow.SizeGB } else { $null }
            FreeGB   = if ($diskRow) { [double]$diskRow.FreeGB } else { $null }
        }
    }
}
