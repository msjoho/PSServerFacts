function Get-RemoteWindowsFeature {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        if (-not (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue)) { return @() }
        Get-WindowsFeature | Where-Object Installed | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; DisplayName = $_.DisplayName }
        }
    } | Select-Object Name, DisplayName
}
