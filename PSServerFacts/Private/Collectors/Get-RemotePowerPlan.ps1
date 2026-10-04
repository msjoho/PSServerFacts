function Get-RemotePowerPlan {
    # Reads the active power scheme + the full list via powercfg. Parsing is
    # locale-tolerant: we use the GUID format which is invariant; the Name is
    # taken verbatim from /list output.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $list = & powercfg.exe /list 2>$null
        $schemes = foreach ($line in $list) {
            if ($line -match 'Power Scheme GUID:\s+(?<g>[0-9a-fA-F-]+)\s+\((?<n>.+?)\)(?<a>\s*\*)?$') {
                [pscustomobject]@{
                    Guid     = $matches['g']
                    Name     = $matches['n']
                    IsActive = [bool]$matches['a']
                }
            }
        }
        $active = $schemes | Where-Object IsActive | Select-Object -First 1
        [pscustomobject]@{
            ActiveSchemeGuid = if ($active) { $active.Guid } else { $null }
            ActiveSchemeName = if ($active) { $active.Name } else { $null }
            AvailableSchemes = @($schemes)
        }
    }
}
