function Get-RemoteInstalledApplication {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $paths = @(
            @{ Hive='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';            Source='Registry' },
            @{ Hive='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Source='Registry-WOW6432' }
        )
        Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'S-1-5-21' -and $_.Name -notmatch '_Classes$' } |
            ForEach-Object {
                $paths += @{ Hive = "Registry::$($_.Name)\Software\Microsoft\Windows\CurrentVersion\Uninstall"; Source = 'Registry-User' }
            }

        $apps = foreach ($p in $paths) {
            if (-not (Test-Path $p.Hive)) { continue }
            Get-ChildItem $p.Hive -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if (-not $props.DisplayName) { return }
                if ($props.SystemComponent -eq 1) { return }
                $installDate = $null
                if ($props.InstallDate -and $props.InstallDate -match '^\d{8}$') {
                    try { $installDate = [datetime]::ParseExact($props.InstallDate,'yyyyMMdd',$null).ToUniversalTime().ToString('o') } catch {}
                }
                [pscustomobject]@{
                    DisplayName     = $props.DisplayName
                    Version         = $props.DisplayVersion
                    Publisher       = $props.Publisher
                    InstallDateUtc  = $installDate
                    InstallLocation = $props.InstallLocation
                    Source          = $p.Source
                    UninstallString = $props.UninstallString
                }
            }
        }
        $apps | Sort-Object DisplayName
    } | Select-Object DisplayName, Version, Publisher, InstallDateUtc, InstallLocation, Source, UninstallString
}
