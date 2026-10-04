function Get-SqlRegistryFacts {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$InstanceName,
        [Parameter(Mandatory)][string]$InstanceId
    )

    Invoke-Command -Session $Session -ArgumentList $InstanceName,$InstanceId -ScriptBlock {
        param($iname, $iid)

        $base = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$iid"

        # Setup
        $setupKey = "$base\Setup"
        $setup = if (Test-Path $setupKey) { Get-ItemProperty -Path $setupKey -ErrorAction SilentlyContinue } else { $null }

        # Updates: enumerate Patches\<KB*>
        $patchesKey = "$base\Setup\Patches"
        $updates = @()
        if (Test-Path $patchesKey) {
            $updates = @(Get-ChildItem $patchesKey -ErrorAction SilentlyContinue | ForEach-Object {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                $installed = $null
                if ($p.PSObject.Properties.Name -contains 'InstallDate' -and $p.InstallDate) {
                    try { $installed = ([datetime]::ParseExact([string]$p.InstallDate, 'yyyyMMdd', $null)).ToUniversalTime().ToString('o') } catch {}
                }
                [pscustomobject]@{
                    KB           = $_.PSChildName
                    Version      = [string]$p.Version
                    InstalledUtc = $installed
                }
            })
        }

        # Installed features: walk shared ConfigurationState across major versions
        $features = @()
        $cfgState = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server' -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match '^\d{2,3}$' } |
            ForEach-Object { Join-Path $_.PSPath 'ConfigurationState' }
        foreach ($k in $cfgState) {
            if (Test-Path $k) {
                $props = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).PSObject.Properties |
                    Where-Object { $_.Name -notlike 'PS*' -and [int]$_.Value -eq 1 }
                $features += @($props.Name)
            }
        }
        $features = $features | Sort-Object -Unique

        # Service accounts via Win32_Service filtered to SQL roles
        $svcs = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
        $accts = [pscustomobject]@{
            Engine  = $null
            Agent   = $null
            Browser = $null
        }
        $engineSvc = $svcs | Where-Object {
            ($_.Name -eq 'MSSQLSERVER' -and $iname -eq 'MSSQLSERVER') -or
            $_.Name -eq "MSSQL`$$iname"
        } | Select-Object -First 1
        $agentName = if ($iname -eq 'MSSQLSERVER') { 'SQLSERVERAGENT' } else { "SQLAgent`$$iname" }
        $agentSvc  = $svcs | Where-Object Name -eq $agentName | Select-Object -First 1
        $browserSvc = $svcs | Where-Object Name -eq 'SQLBrowser' | Select-Object -First 1

        if ($engineSvc) {
            $accts.Engine = [pscustomobject]@{ Name=$engineSvc.Name; Account=$engineSvc.StartName; StartMode=$engineSvc.StartMode; State=$engineSvc.State }
        }
        if ($agentSvc) {
            $accts.Agent = [pscustomobject]@{ Name=$agentSvc.Name; Account=$agentSvc.StartName; StartMode=$agentSvc.StartMode; State=$agentSvc.State }
        }
        if ($browserSvc) {
            $accts.Browser = [pscustomobject]@{ Name=$browserSvc.Name; Account=$browserSvc.StartName; StartMode=$browserSvc.StartMode; State=$browserSvc.State }
        }

        # Default data/log paths from MSSQLServer\Parameters startup args (-d / -l)
        # or from MSSQLServer\DefaultData / DefaultLog
        $defaultDataPath = $null
        $defaultLogPath  = $null
        $paramsKey = "$base\MSSQLServer"
        if (Test-Path $paramsKey) {
            $params = Get-ItemProperty -Path $paramsKey -ErrorAction SilentlyContinue
            $defaultDataPath = $params.DefaultData
            $defaultLogPath  = $params.DefaultLog
        }
        $argsKey = "$base\MSSQLServer\Parameters"
        if (Test-Path $argsKey) {
            $argsObj = Get-ItemProperty -Path $argsKey -ErrorAction SilentlyContinue
            foreach ($name in $argsObj.PSObject.Properties.Name) {
                if ($name -like 'SQLArg*') {
                    $v = [string]$argsObj.$name
                    if ($v -like '-d*' -and -not $defaultDataPath) { $defaultDataPath = Split-Path -Parent $v.Substring(2) }
                    elseif ($v -like '-l*' -and -not $defaultLogPath) { $defaultLogPath = Split-Path -Parent $v.Substring(2) }
                }
            }
        }

        [pscustomobject]@{
            Version           = if ($setup) { [string]$setup.Version }     else { $null }
            Edition           = if ($setup) { [string]$setup.Edition }     else { $null }
            EditionType       = if ($setup) { [string]$setup.EditionType } else { $null }
            PatchLevel        = if ($setup) { [string]$setup.PatchLevel }  else { $null }
            Updates           = @($updates)
            InstalledFeatures = @($features)
            ServiceAccounts   = $accts
            DefaultDataPath   = $defaultDataPath
            DefaultLogPath    = $defaultLogPath
        }
    } | Select-Object Version,Edition,EditionType,PatchLevel,Updates,InstalledFeatures,ServiceAccounts,DefaultDataPath,DefaultLogPath
}
