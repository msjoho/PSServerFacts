function Get-RemoteLocalUser {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $exclude = 500,501,503,504    # Administrator, Guest, DefaultAccount, WDAGUtilityAccount
        Get-LocalUser | Where-Object {
            $rid = [int](($_.SID.Value -split '-')[-1])
            $rid -notin $exclude
        } | ForEach-Object {
            [pscustomobject]@{
                Name                 = $_.Name
                Enabled              = $_.Enabled
                PasswordLastSetUtc   = if ($_.PasswordLastSet) { $_.PasswordLastSet.ToUniversalTime().ToString('o') } else { $null }
                PasswordNeverExpires = $_.PasswordNeverExpires
                Description          = $_.Description
                Sid                  = $_.SID.Value
            }
        }
    } | Select-Object Name, Enabled, PasswordLastSetUtc, PasswordNeverExpires, Description, Sid
}
