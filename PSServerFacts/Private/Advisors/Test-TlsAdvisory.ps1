function Test-TlsAdvisory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][object]$Roles
    )

    if (-not $Result.PSObject.Properties['Tls']) { return @() }
    $tls = $Result.Tls
    if ($null -eq $tls -or -not $tls.Protocols) { return @() }

    foreach ($p in @($tls.Protocols)) {
        if (-not $p.Enabled) { continue }
        switch -Regex ($p.Name) {
            '^SSL ' {
                [pscustomobject]@{
                    Section  = 'Tls'; Severity = 'Critical'; Rule = 'TlsLegacySsl'
                    Message  = "$($p.Name) is enabled ($($p.Side)). SSL is broken; disable both Client and Server keys."
                    Context  = @{ Protocol=$p.Name; Side=$p.Side }
                }
            }
            '^TLS 1\.[01]$' {
                [pscustomobject]@{
                    Section  = 'Tls'; Severity = 'Warning'; Rule = 'TlsLegacyTls'
                    Message  = "$($p.Name) is enabled ($($p.Side)). Deprecated — disable unless a known client still needs it."
                    Context  = @{ Protocol=$p.Name; Side=$p.Side }
                }
            }
        }
    }
}
