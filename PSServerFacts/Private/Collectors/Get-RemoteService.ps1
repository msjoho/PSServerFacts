function Get-RemoteService {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        # -ErrorAction Stop: a CIM/WMI/DCOM failure becomes a terminating exception
        # that propagates back through Invoke-Command instead of silently emitting zero results.
        # No leading-comma wrapper: caller is responsible for @(...) wrapping if they need
        # to preserve array shape for single-element results.
        Get-CimInstance Win32_Service -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{
                Name        = $_.Name
                DisplayName = $_.DisplayName
                State       = $_.State
                StartMode   = $_.StartMode
                PathName    = $_.PathName
                StartName   = $_.StartName
                Description = $_.Description
            }
        }
    } | Select-Object Name, DisplayName, State, StartMode, PathName, StartName, Description
}
