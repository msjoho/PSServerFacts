function Get-SqlBackupDirectoryAcl {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [AllowNull()][AllowEmptyString()][string]$BackupDirectory
    )

    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) { return }

    $paths = @($BackupDirectory -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    # The probe runs against any path on the host where it's invoked. Used for both
    # jumphost-side (no double-hop, full Kerberos) and target-side (Kerberos can't
    # forward to a UNC server beyond the first hop) reads.
    $probeAcl = {
        param($p)

        $reachable = Test-Path -LiteralPath $p -ErrorAction SilentlyContinue
        if (-not $reachable) {
            return [pscustomobject]@{
                Path     = $p
                PathType = if ($p.StartsWith('\\')) { 'UNC' } else { 'Local' }
                Error    = 'Path not accessible'
            }
        }

        $owner = $null; $inherit = 'Unknown'; $aces = @(); $sourceKind = 'GetAcl'
        # NTFSSecurity ships these three cmdlets as a set — but partial / older installs
        # sometimes have Get-NTFSAccess without the others. Require all three before
        # taking the NTFSSecurity branch; otherwise fall through to built-in Get-Acl.
        $hasNtfsSec = (Get-Command Get-NTFSAccess,Get-NTFSAccessInheritance,Get-NTFSOwner -ErrorAction SilentlyContinue).Count -eq 3
        try {
            if ($hasNtfsSec) {
                $sourceKind = 'NTFSSecurity'
                $owner   = (Get-NTFSOwner -Path $p -ErrorAction Stop).Owner
                $inherit = if ((Get-NTFSAccessInheritance -Path $p -ErrorAction Stop).AccessInheritanceEnabled) { 'Enabled' } else { 'Disabled' }
                $aces = @(Get-NTFSAccess -Path $p -ErrorAction Stop)
            } else {
                $sourceKind = 'GetAcl'
                $acl = Get-Acl -Path $p -ErrorAction Stop
                $owner   = [string]$acl.Owner
                $inherit = if ($acl.AreAccessRulesProtected) { 'Disabled' } else { 'Enabled' }
                $aces = @($acl.Access)
            }
        } catch {
            return [pscustomobject]@{
                Path     = $p
                PathType = if ($p.StartsWith('\\')) { 'UNC' } else { 'Local' }
                Error    = $_.Exception.Message
            }
        }

        [pscustomobject]@{
            Path        = $p
            PathType    = if ($p.StartsWith('\\')) { 'UNC' } else { 'Local' }
            Owner       = $owner
            Inheritance = $inherit
            RawAces     = $aces
            SourceKind  = $sourceKind
        }
    }

    foreach ($path in $paths) {
        $isUnc = $path.StartsWith('\\')

        # For UNC paths, prefer the jumphost. Reading the share from inside the target
        # session usually fails with "Access is denied" — that's the Kerberos double-hop
        # constraint, since the target can't forward the user's creds to the file server.
        # The jumphost holds primary creds and can reach the UNC directly.
        # For local paths (D:\Backup etc.), only the target can see them.
        $probe = $null
        $source = $null
        if ($isUnc) {
            $probe = & $probeAcl $path
            $source = 'Jumphost'
            if ($probe.Error) {
                $jumphostErr = $probe.Error
                $probe = Invoke-Command -Session $Session -ArgumentList $path -ScriptBlock $probeAcl
                $source = 'Target'
                if ($probe.Error) {
                    $probe.Error = "Jumphost: $jumphostErr; Target: $($probe.Error)"
                }
            }
        } else {
            $probe = Invoke-Command -Session $Session -ArgumentList $path -ScriptBlock $probeAcl
            $source = 'Target'
        }

        if ($probe.Error) {
            [pscustomobject]@{
                Path     = $probe.Path
                PathType = $probe.PathType
                ReadFrom = $source
                Error    = $probe.Error
            }
            continue
        }

        # Normalize and filter to non-inherited only.
        # ConvertTo-NtfsPermissionEntry outputs: Path, Account, Rights, AppliesTo, Inherited, AccessControlType.
        $entries = foreach ($ace in $probe.RawAces | Where-Object { -not $_.IsInherited }) {
            ConvertTo-NtfsPermissionEntry -Ace $ace -Path $probe.Path -SourceKind $probe.SourceKind
        }

        [pscustomobject]@{
            Path        = $probe.Path
            PathType    = $probe.PathType
            ReadFrom    = $source
            Owner       = $probe.Owner
            Inheritance = $probe.Inheritance
            Entries     = @($entries)
        }
    }
}
