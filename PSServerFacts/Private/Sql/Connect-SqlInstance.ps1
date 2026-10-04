# Stub dbatools cmdlets for hosts that don't have the module installed.
# Allows tests on dev machines and avoids hard prereq.
if (-not (Get-Command Connect-DbaInstance -ErrorAction SilentlyContinue)) {
    function Connect-DbaInstance { param($SqlInstance, $SqlCredential) throw 'dbatools not installed' }
}

function Connect-SqlInstance {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][string]$InstanceName,
        [pscredential]$SqlCredential
    )

    # We always connect from the jumphost. An earlier design tried target-side first,
    # but the SMO Server object returned from inside Invoke-Command -Session loses
    # fidelity when serialized back across the PSSession boundary — its .ToString()
    # becomes "[<host>]" (with literal brackets), which downstream Get-Dba* cmdlets
    # can't parse as a DbaInstanceParameter. dbatools' connection pool is local to
    # whoever runs the cmdlet, so jumphost-side is the only mechanism that actually
    # works for follow-up queries.
    if (-not (Get-Module -ListAvailable -Name dbatools)) {
        return [pscustomobject]@{
            ConnectedInstance = $null
            ConnectionMethod  = 'RegistryOnly'
            Error             = 'dbatools module not available on jumphost'
        }
    }

    $sqlInstFqdn = if ($InstanceName -eq 'MSSQLSERVER') { $ComputerName } else { "$ComputerName\$InstanceName" }
    $connectArgs = @{ SqlInstance = $sqlInstFqdn; TrustServerCertificate = $true }
    if ($SqlCredential) { $connectArgs['SqlCredential'] = $SqlCredential }

    try {
        $c = Connect-DbaInstance @connectArgs -ErrorAction Stop
        return [pscustomobject]@{
            ConnectedInstance = $c
            ConnectionMethod  = 'JumphostSideDbatools'
            Error             = $null
        }
    } catch {
        return [pscustomobject]@{
            ConnectedInstance = $null
            ConnectionMethod  = 'Failed'
            Error             = $_.Exception.Message
        }
    }
}
