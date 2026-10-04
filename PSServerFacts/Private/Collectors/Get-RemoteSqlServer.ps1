function Get-RemoteSqlServer {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$SqlCredential,
        [AllowNull()][AllowEmptyCollection()][object[]]$Disks,
        [switch]$IncludeBackupDirectoryRoot
    )

    $instances = @(Get-SqlInstanceList -Session $Session -ServerName $ComputerName)
    if ($instances.Count -eq 0) { return $null }

    $out = foreach ($inst in $instances) {
        $tier1 = Get-SqlRegistryFacts -Session $Session -InstanceName $inst.InstanceName -InstanceId $inst.InstanceId

        $connArgs = @{ Session = $Session; ComputerName = $ComputerName; InstanceName = $inst.InstanceName }
        if ($SqlCredential) { $connArgs['SqlCredential'] = $SqlCredential }
        $conn = Connect-SqlInstance @connArgs

        $tier2 = $null
        $liveQueryError = $null
        if ($conn.ConnectedInstance) {
            try { $tier2 = Get-SqlLiveData -ConnectedInstance $conn.ConnectedInstance }
            catch { $liveQueryError = $_.Exception.Message }
        }

        $diskLayout = if ($tier2) { @(Get-SqlDiskLayout -Databases $tier2.Databases -Disks $Disks) } else { @() }

        # Probe the per-instance subfolder that Ola Hallengren's backup script writes
        # into (well-known convention used by most large estates). For default
        # instance: <BackupDir>\<ShortHost>; for named instance:
        # <BackupDir>\<ShortHost>$<InstanceName>. The configured root is skipped by
        # default (rarely actionable — usually a generic share grant) and only
        # included when -IncludeBackupDirectoryRoot is set.
        $aclList = @()
        if ($tier2 -and $tier2.Configuration.BackupDirectory) {
            $shortHost = ($ComputerName -split '\.')[0]
            $subdirName = if ($inst.InstanceName -eq 'MSSQLSERVER') { $shortHost } else { "$shortHost`$$($inst.InstanceName)" }
            $candidatePaths = New-Object System.Collections.Generic.List[string]
            foreach ($base in @($tier2.Configuration.BackupDirectory -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                if ($IncludeBackupDirectoryRoot) { $candidatePaths.Add($base) | Out-Null }
                $candidatePaths.Add((Join-Path $base $subdirName)) | Out-Null
            }
            $aclList = @(Get-SqlBackupDirectoryAcl -Session $Session -BackupDirectory ($candidatePaths -join ';'))
        }

        [pscustomobject]@{
            InstanceName         = $inst.InstanceName
            ServerName           = $inst.ServerName
            InstanceId           = $inst.InstanceId
            Version              = $tier1.Version
            Edition              = $tier1.Edition
            PatchLevel           = $tier1.PatchLevel
            Collation            = if ($tier2) { $tier2.Collation } else { $null }
            AuthenticationMode   = if ($tier2) { $tier2.AuthenticationMode } else { $null }
            IsClustered          = if ($tier2) { $tier2.IsClustered } else { $null }
            InstalledFeatures    = @($tier1.InstalledFeatures)
            InstalledUpdates     = @($tier1.Updates)
            ServiceAccounts      = $tier1.ServiceAccounts
            Configuration        = if ($tier2) { $tier2.Configuration } else { $null }
            Logins               = if ($tier2) { @($tier2.Logins) } else { @() }
            OrphanDatabaseUsers  = if ($tier2) { @($tier2.OrphanDatabaseUsers) } else { @() }
            LinkedServers        = if ($tier2) { @($tier2.LinkedServers) } else { @() }
            Databases            = if ($tier2) { @($tier2.Databases) } else { @() }
            DiskLayout           = $diskLayout
            AvailabilityGroups   = if ($tier2) { @($tier2.AvailabilityGroups) } else { @() }
            AgentJobs            = if ($tier2) { @($tier2.AgentJobs) } else { @() }
            Backups              = if ($tier2) { @($tier2.Backups) } else { @() }
            BackupDirectoryAcls  = $aclList
            ConnectionMethod     = $conn.ConnectionMethod
            ConnectionError      = $conn.Error
            LiveQueryError       = $liveQueryError
            LiveQueryAvailable   = [bool]$tier2
        }
    }

    # Empty-array preservation across function boundary
    $PSCmdlet.WriteObject(@($out), $true)
}
