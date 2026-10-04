# Stubs for environments without dbatools (tests, dev jumphost without module).
foreach ($cmd in 'Get-DbaInstanceProperty','Get-DbaLogin','Get-DbaServerRoleMember',
                 'Get-DbaDbUser','Get-DbaDbRoleMember','Get-DbaLinkedServer',
                 'Get-DbaDatabase','Get-DbaDbFile',
                 'Get-DbaAvailabilityGroup','Get-DbaAgReplica','Get-DbaAgListener','Get-DbaAgDatabase',
                 'Get-DbaAgentJob','Get-DbaDbBackupHistory') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)) {
        Invoke-Expression "function $cmd { throw 'dbatools not installed' }"
    }
}

function Get-SqlLiveData {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$ConnectedInstance
    )

    # --- Instance properties → Configuration + AuthenticationMode + IsClustered + Collation ---
    $props = @(Get-DbaInstanceProperty -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $propValue = {
        param([string]$name)
        ($props | Where-Object Name -eq $name | Select-Object -First 1).Value
    }

    $config = [pscustomobject]@{
        Collation                   = [string](& $propValue 'Collation')
        MaxMemoryMB                 = [int](& $propValue 'MaxMemory')
        MinMemoryMB                 = [int](& $propValue 'MinMemory')
        MaxDop                      = [int](& $propValue 'MaxDop')
        CostThresholdForParallelism = [int](& $propValue 'CostThresholdForParallelism')
        DefaultDataPath             = [string](& $propValue 'DefaultFile')
        DefaultLogPath              = [string](& $propValue 'DefaultLog')
        BackupDirectory             = [string](& $propValue 'BackupDirectory')
    }
    $collation        = [string](& $propValue 'Collation')
    $isClustered      = [bool] (& $propValue 'IsClustered')
    $authMode         = [string](& $propValue 'LoginMode')

    # --- Logins + ServerRoles + DatabaseAccess (SID join via dbatools) ---
    $rawLogins   = @(Get-DbaLogin             -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $rawSrvRoles = @(Get-DbaServerRoleMember  -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $rawDbUsers  = @(Get-DbaDbUser            -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $rawDbRoles  = @(Get-DbaDbRoleMember      -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)

    # Group DB role memberships by (Database, UserName) → roles list
    $dbRoleLookup = @{}
    foreach ($m in $rawDbRoles) {
        $key = "$($m.Database)|$($m.UserName)"
        if (-not $dbRoleLookup.ContainsKey($key)) { $dbRoleLookup[$key] = @() }
        $dbRoleLookup[$key] += [string]$m.Role
    }

    # Map login → DatabaseAccess; collect orphans separately
    $orphanUsers = New-Object System.Collections.Generic.List[object]
    $logins = foreach ($l in $rawLogins) {
        $serverRoles = @($rawSrvRoles | Where-Object Login -eq $l.Name | ForEach-Object Role | Sort-Object -Unique)
        $dbAccess = foreach ($u in ($rawDbUsers | Where-Object Login -eq $l.Name)) {
            [pscustomobject]@{
                Database     = [string]$u.Database
                DatabaseUser = [string]$u.Name
                Roles        = @($dbRoleLookup["$($u.Database)|$($u.Name)"] | Where-Object { $_ })
            }
        }
        [pscustomobject]@{
            Name           = [string]$l.Name
            Type           = [string]$l.LoginType
            Disabled       = [bool]$l.IsDisabled
            Locked         = [bool]$l.IsLocked
            ServerRoles    = $serverRoles
            DatabaseAccess = @($dbAccess)
        }
    }
    foreach ($u in ($rawDbUsers | Where-Object { -not $_.Login })) {
        $orphanUsers.Add([pscustomobject]@{
            Database     = [string]$u.Database
            DatabaseUser = [string]$u.Name
            Roles        = @($dbRoleLookup["$($u.Database)|$($u.Name)"] | Where-Object { $_ })
        }) | Out-Null
    }

    # --- Linked servers ---
    $linked = @(Get-DbaLinkedServer -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            Name         = [string]$_.Name
            Product      = [string]$_.ProductName
            DataSource   = [string]$_.DataSource
            SecurityMode = [string]$_.SecurityMode
        }
    })

    # --- Databases + Files ---
    $rawDbs    = @(Get-DbaDatabase -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $rawFiles  = @(Get-DbaDbFile   -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $databases = foreach ($db in $rawDbs) {
        $files = @($rawFiles | Where-Object Database -eq $db.Name | ForEach-Object {
            $type = if ([string]$_.TypeDescription -eq 'LOG') { 'Log' } else { 'Data' }
            [pscustomobject]@{
                Type         = $type
                LogicalName  = [string]$_.LogicalName
                PhysicalPath = [string]$_.PhysicalName
                SizeMB       = [double]$_.SizeMB
            }
        })
        [pscustomobject]@{
            Name               = [string]$db.Name
            IsSystem           = [bool]$db.IsSystemObject
            Collation          = [string]$db.Collation
            RecoveryModel      = [string]$db.RecoveryModel
            CompatibilityLevel = [int](([string]$db.CompatibilityLevel) -replace '\D','')
            Owner              = [string]$db.Owner
            Status             = [string]$db.Status
            SizeMB             = [double]$db.SizeMB
            Files              = $files
        }
    }

    # --- Availability Groups ---
    $rawAgs = @(Get-DbaAvailabilityGroup -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
    $ags = foreach ($ag in $rawAgs) {
        $reps = @(Get-DbaAgReplica   -SqlInstance $ConnectedInstance -AvailabilityGroup $ag.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name             = [string]$_.Name
                Role             = [string]$_.Role
                AvailabilityMode = [string]$_.AvailabilityMode
                FailoverMode     = [string]$_.FailoverMode
                SeedingMode      = [string]$_.SeedingMode
            }
        })
        $lst  = (Get-DbaAgListener -SqlInstance $ConnectedInstance -AvailabilityGroup $ag.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Select-Object -First 1)
        $lstObj = if ($lst) {
            [pscustomobject]@{
                Name = [string]$lst.Name
                IPs  = @($lst.AvailabilityGroupListenerIPAddresses.IPAddress | ForEach-Object { [string]$_ })
                Port = [int]$lst.PortNumber
            }
        } else { $null }
        $dbs = @(Get-DbaAgDatabase -SqlInstance $ConnectedInstance -AvailabilityGroup $ag.Name -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | ForEach-Object Name)
        [pscustomobject]@{
            Name        = [string]$ag.Name
            ClusterType = [string]$ag.ClusterType
            Listener    = $lstObj
            Replicas    = $reps
            Databases   = $dbs
        }
    }

    # --- Agent Jobs (with schedule rendering via Format-SqlAgentScheduleSummary) ---
    $jobs = @(Get-DbaAgentJob -SqlInstance $ConnectedInstance -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | ForEach-Object {
        $j = $_
        $schedules = foreach ($s in @($j.JobSchedules)) {
            [pscustomobject]@{
                Name              = [string]$s.Name
                Summary           = (Format-SqlAgentScheduleSummary -Schedule $s)
                Enabled           = [bool]$s.IsEnabled
                FrequencyType     = [string]$s.FrequencyType
                FrequencyInterval = [int]$s.FrequencyInterval
                ActiveStartTime   = if ($s.ActiveStartTimeOfDay) { ([timespan]$s.ActiveStartTimeOfDay).ToString() } else { $null }
                DaysOfWeek        = if ($s.DaysOfWeek) { [string]$s.DaysOfWeek } else { $null }
            }
        }
        [pscustomobject]@{
            Name           = [string]$j.Name
            Enabled        = [bool]$j.IsEnabled
            Owner          = [string]$j.OwnerLoginName
            Category       = [string]$j.Category
            LastRunUtc     = if ($j.LastRunDate) { ([datetime]$j.LastRunDate).ToUniversalTime().ToString('o') } else { $null }
            LastRunOutcome = [string]$j.LastRunOutcome
            NextRunUtc     = if ($j.NextRunDate) { ([datetime]$j.NextRunDate).ToUniversalTime().ToString('o') } else { $null }
            Schedules      = @($schedules)
        }
    })

    # --- Backups (latest of each type per DB) ---
    # Querying with combined -LastFull -LastDiff -LastLog only returns rows for
    # databases that have ALL THREE backup types in msdb history. Databases with
    # only Full+Diff (no Log) or only Full (no Diff/Log) get excluded entirely.
    # Query each type separately and union by database.
    $bhArgs = @{ SqlInstance = $ConnectedInstance; ExcludeDatabase = 'tempdb'; ErrorAction = 'SilentlyContinue'; WarningAction = 'SilentlyContinue' }
    $rawFulls = @(Get-DbaDbBackupHistory @bhArgs -LastFull)
    $rawDiffs = @(Get-DbaDbBackupHistory @bhArgs -LastDiff)
    $rawLogs  = @(Get-DbaDbBackupHistory @bhArgs -LastLog)

    $shapeBackup = {
        param($b)
        if (-not $b) { return $null }
        [pscustomobject]@{
            BackupAtUtc     = if ($b.End) { ([datetime]$b.End).ToUniversalTime().ToString('o') } else { $null }
            Path            = if ($b.Path -and $b.Path.Count -gt 0) { [string]$b.Path[0] } else { $null }
            SizeMB          = if ($b.TotalSize) { [math]::Round([double]$b.TotalSize / 1MB, 1) } else { $null }
            DestinationType = [string]$b.DeviceType
        }
    }
    $dbNames = @($rawFulls + $rawDiffs + $rawLogs | ForEach-Object { [string]$_.Database } | Sort-Object -Unique | Where-Object { $_ })
    $backups = foreach ($db in $dbNames) {
        $f = $rawFulls | Where-Object { [string]$_.Database -eq $db } | Select-Object -First 1
        $d = $rawDiffs | Where-Object { [string]$_.Database -eq $db } | Select-Object -First 1
        $l = $rawLogs  | Where-Object { [string]$_.Database -eq $db } | Select-Object -First 1
        [pscustomobject]@{
            DatabaseName = $db
            LastFull     = (& $shapeBackup $f)
            LastDiff     = (& $shapeBackup $d)
            LastLog      = (& $shapeBackup $l)
        }
    }

    [pscustomobject]@{
        Configuration       = $config
        Collation           = $collation
        AuthenticationMode  = $authMode
        IsClustered         = $isClustered
        Logins              = @($logins)
        OrphanDatabaseUsers = @($orphanUsers.ToArray())
        LinkedServers       = $linked
        Databases           = @($databases)
        AvailabilityGroups  = @($ags)
        AgentJobs           = $jobs
        Backups             = @($backups)
    }
}
