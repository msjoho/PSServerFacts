function Get-RemoteShare {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][ValidateSet('Root','Children','Recursive')][string]$NtfsDepth,
        [Parameter(Mandatory)][ValidateSet('Auto','Install','None')][string]$NtfsSecurityProvisioning,
        [string]$RunId = ([guid]::NewGuid().ToString('N')),
        [string]$JumphostModulePath
    )

    Invoke-Command -Session $Session -ArgumentList $NtfsDepth,$NtfsSecurityProvisioning,$RunId,$JumphostModulePath -ScriptBlock {
        param($depth,$prov,$runId,$jumphostModulePath)

        $useNtfsSec = $false
        $errors = @()

        $alreadyHave = [bool](Get-Module -ListAvailable -Name NTFSSecurity)
        if ($alreadyHave) {
            Import-Module NTFSSecurity -ErrorAction SilentlyContinue
            $useNtfsSec = [bool](Get-Command Get-NTFSAccess -ErrorAction SilentlyContinue)
        } elseif ($prov -eq 'Install') {
            try {
                Install-Module NTFSSecurity -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
                Import-Module NTFSSecurity -ErrorAction Stop
                $useNtfsSec = $true
            } catch { $errors += "Install-Module NTFSSecurity failed: $($_.Exception.Message)" }
        } elseif ($prov -eq 'Auto' -and $jumphostModulePath) {
            try {
                Import-Module $jumphostModulePath -ErrorAction Stop
                $useNtfsSec = [bool](Get-Command Get-NTFSAccess -ErrorAction SilentlyContinue)
            } catch { $errors += "Import-Module from temp copy failed: $($_.Exception.Message)" }
        }

        function Read-Aces([string]$Path,[string]$Depth,[bool]$UseNtfsSec) {
            $paths = switch ($Depth) {
                'Root'      { ,@($Path) }
                'Children'  { ,@(@($Path) + (Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue).FullName) }
                'Recursive' { ,@(@($Path) + (Get-ChildItem -LiteralPath $Path -Recurse -Directory -ErrorAction SilentlyContinue).FullName) }
            }
            foreach ($p in $paths) {
                try {
                    if ($UseNtfsSec) {
                        Get-NTFSAccess -Path $p -ExcludeInherited:$false | ForEach-Object {
                            $_ | Add-Member -NotePropertyName _path -NotePropertyValue $p -Force -PassThru
                        }
                    } else {
                        $acl = Get-Acl -LiteralPath $p -ErrorAction Stop
                        $acl.Access | ForEach-Object {
                            $_ | Add-Member -NotePropertyName _path -NotePropertyValue $p -Force -PassThru
                        }
                    }
                } catch {
                    $script:perPathErrors += "ACL read failed for $p : $($_.Exception.Message)"
                }
            }
        }

        $shares = Get-CimInstance Win32_Share | Where-Object { $_.Type -eq 0 -or $_.Type -eq 2147483648 }

        $shares | ForEach-Object {
            $share = $_
            $script:perPathErrors = @()

            $sharePerms = try {
                Get-SmbShareAccess -Name $share.Name -ErrorAction Stop | ForEach-Object {
                    [pscustomobject]@{
                        Account           = $_.AccountName
                        AccessRight       = $_.AccessRight
                        AccessControlType = $_.AccessControlType
                    }
                }
            } catch { @() }

            $aces = @()
            if ($share.Path -and (Test-Path -LiteralPath $share.Path)) {
                $aces = @(Read-Aces -Path $share.Path -Depth $depth -UseNtfsSec:$useNtfsSec)
            } else {
                $perPathErrors += "Share path not accessible: $($share.Path)"
            }

            [pscustomobject]@{
                Name             = $share.Name
                Path             = $share.Path
                Description      = $share.Description
                SharePermissions = @($sharePerms)
                NtfsRawAces      = @($aces)
                NtfsSourceKind   = if ($useNtfsSec) { 'NTFSSecurity' } else { 'GetAcl' }
                NtfsErrors       = @($errors + $perPathErrors)
            }
        }
    } | Select-Object Name, Path, Description, SharePermissions, NtfsRawAces, NtfsSourceKind, NtfsErrors
}
