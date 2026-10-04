# Stub so Pester Mock has a target when the ActiveDirectory module isn't loaded
# (e.g. in unit tests or on a host without RSAT). Real Get-ADDomain shadows this
# once the ActiveDirectory module is imported.
if (-not (Get-Command Get-ADDomain -ErrorAction SilentlyContinue)) {
    function Get-ADDomain {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline)]$Identity, $Server)
        throw "ActiveDirectory module is not loaded; install RSAT or import ActiveDirectory."
    }
}

function Resolve-DomainFqdn {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$NetbiosName,
        [Parameter(Mandatory)][hashtable]$Cache
    )
    $key = $NetbiosName.ToUpperInvariant()
    if ($Cache.ContainsKey($key)) { return $Cache[$key] }

    $fqdn = $null
    try {
        $dom = Get-ADDomain -Identity $key -ErrorAction Stop
        $fqdn = $dom.DNSRoot
    } catch {
        $fqdn = $null
    }
    $Cache[$key] = $fqdn
    return $fqdn
}
