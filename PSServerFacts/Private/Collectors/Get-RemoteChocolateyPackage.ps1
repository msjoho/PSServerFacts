function Get-RemoteChocolateyPackage {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $choco = Get-Command choco.exe -ErrorAction SilentlyContinue
        if (-not $choco) { return @() }
        $raw = & choco.exe list -lo -r 2>$null
        $raw | Where-Object { $_ -match '\|' } | ForEach-Object {
            $parts = $_ -split '\|',2
            [pscustomobject]@{ Id = $parts[0]; Version = $parts[1] }
        }
    } | Select-Object Id, Version
}
