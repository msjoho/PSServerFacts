# Bootstrap.ps1 — loaded by all *.Tests.ps1 via . $PSScriptRoot/Bootstrap.ps1
$script:RepoRoot = Split-Path $PSScriptRoot -Parent
$global:RepoRoot = $script:RepoRoot

# Remove any stale copy from a prior test run before re-importing.
Get-Module PSServerFacts | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module (Join-Path $RepoRoot 'PSServerFacts/PSServerFacts.psd1') -Force -Global -ErrorAction Stop
