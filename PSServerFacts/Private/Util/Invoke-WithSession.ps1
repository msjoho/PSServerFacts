function Invoke-WithSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [pscredential]$Credential
    )
    $sessionParams = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
    if ($Credential) { $sessionParams['Credential'] = $Credential }
    $session = New-PSSession @sessionParams
    try {
        & $ScriptBlock $session
    } finally {
        if ($session) { Remove-PSSession -Id $session.Id -ErrorAction SilentlyContinue }
    }
}
