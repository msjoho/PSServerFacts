function Get-SqlInstanceList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$ServerName
    )

    $raw = Invoke-Command -Session $Session -ScriptBlock {
        $key = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL'
        if (-not (Test-Path $key)) { return @() }
        $props = (Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' }
        foreach ($p in $props) {
            [pscustomobject]@{ InstanceName = $p.Name; InstanceId = [string]$p.Value }
        }
    }

    foreach ($i in @($raw | Where-Object { $null -ne $_ })) {
        $sn = if ($i.InstanceName -eq 'MSSQLSERVER') { $ServerName } else { "$ServerName\$($i.InstanceName)" }
        $i | Add-Member -NotePropertyName ServerName -NotePropertyValue $sn -Force
        $i
    }
}
