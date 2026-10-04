function Get-RemoteFirewallRule {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        Get-NetFirewallRule -Enabled True | ForEach-Object {
            $rule = $_
            $port    = $rule | Get-NetFirewallPortFilter        -ErrorAction SilentlyContinue
            $addr    = $rule | Get-NetFirewallAddressFilter     -ErrorAction SilentlyContinue
            $app     = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            [pscustomobject]@{
                DisplayName   = $rule.DisplayName
                Direction     = [string]$rule.Direction
                Action        = [string]$rule.Action
                Profile       = [string]$rule.Profile
                Enabled       = [bool]$rule.Enabled
                LocalPort     = ($port.LocalPort -join ',')
                Protocol      = $port.Protocol
                Program       = $app.Program
                RemoteAddress = ($addr.RemoteAddress -join ',')
                Group         = $rule.Group
            }
        }
    } | Select-Object DisplayName, Direction, Action, Profile, Enabled, LocalPort, Protocol, Program, RemoteAddress, Group
}
