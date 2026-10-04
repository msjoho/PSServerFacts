@{
    # Firewall rules whose Group field starts with any of these are considered
    # Windows-shipped defaults.
    #   @FirewallAPI.dll    — core Windows firewall rules (file/print, RPC, etc.)
    #   @%SystemRoot%\      — optional features (RDS, Hyper-V, Containers, …)
    #   @%ProgramFiles%\    — MSI-installed Windows components using resource indirection
    #   @{Microsoft.        — AppX/UWP package rules (Cortana, SecHealthUI, AAD broker, …)
    #   @icsvc.dll          — Internet Connection Sharing
    #   Shell Input Application — touch/pen input rules
    #   DiagTrack           — connected user experience / telemetry
    Prefixes = @(
        '@FirewallAPI.dll'
        '@%SystemRoot%\'
        '@%ProgramFiles%'
        '@{Microsoft.'
        '@icsvc.dll'
        'Shell Input Application'
        'DiagTrack'
    )
}
