# PSServerFacts module loader.
# Private/ is dot-sourced first so Public functions can reference helpers.
# Exports are driven by the manifest, not by this file.
$ErrorActionPreference = 'Stop'
foreach ($scope in 'Private','Public') {
    $root = Join-Path $PSScriptRoot $scope
    if (-not (Test-Path $root)) { continue }
    Get-ChildItem -Path $root -Recurse -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}
