function Get-RemoteDefender {
    # Combines Get-MpComputerStatus (engine state) + Get-MpPreference (exclusions).
    # Both can throw on hosts where Defender isn't installed — returns null fields
    # gracefully rather than failing the whole section.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $status = $null; $pref = $null
        try { $status = Get-MpComputerStatus -ErrorAction Stop } catch { }
        try { $pref   = Get-MpPreference     -ErrorAction Stop } catch { }
        $engine = [pscustomobject]@{
            AntivirusEnabled                = if ($status) { [bool]$status.AntivirusEnabled }                else { $null }
            RealTimeProtectionEnabled       = if ($status) { [bool]$status.RealTimeProtectionEnabled }       else { $null }
            TamperProtected                 = if ($status) { [bool]$status.IsTamperProtected }               else { $null }
            AMServiceEnabled                = if ($status) { [bool]$status.AMServiceEnabled }                else { $null }
            AntivirusSignatureLastUpdatedUtc= if ($status -and $status.AntivirusSignatureLastUpdated) { $status.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o') } else { $null }
            AntivirusSignatureAgeDays       = if ($status) { [int]$status.AntivirusSignatureAge }            else { $null }
        }
        $excl = [pscustomobject]@{
            Paths      = if ($pref) { @($pref.ExclusionPath)      } else { @() }
            Extensions = if ($pref) { @($pref.ExclusionExtension) } else { @() }
            Processes  = if ($pref) { @($pref.ExclusionProcess)   } else { @() }
        }
        [pscustomobject]@{ Engine=$engine; Exclusions=$excl }
    }
}
