function New-RunFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Root)

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HHmmss_fff')
    $folder = Join-Path -Path $Root -ChildPath $stamp
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    return (Resolve-Path $folder).Path
}
