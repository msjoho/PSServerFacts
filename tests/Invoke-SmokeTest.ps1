[CmdletBinding()]
param(
    [string]$Target = 'localhost',
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\output\smoke')
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

& "$repoRoot/Invoke-ServerAssessment.ps1" -ComputerName $Target -OutputRoot $OutputRoot -ThrottleLimit 1
$exit = $LASTEXITCODE

# Find the run folder we just produced.
$runFolder = Get-ChildItem -Directory $OutputRoot | Sort-Object Name -Descending | Select-Object -First 1
if (-not $runFolder) { throw "No run folder produced under $OutputRoot" }

$safeName = ($Target -replace '[^A-Za-z0-9._-]', '_')
$jsonFile = Join-Path $runFolder.FullName "$safeName.json"

if (-not (Test-Path $jsonFile)) { throw "Expected output file not found: $jsonFile" }

$schema = Get-Content "$repoRoot/tests/schemas/server-assessment.schema.json" -Raw
$json   = Get-Content $jsonFile -Raw

if (-not (Test-Json -Json $json -Schema $schema)) {
    throw "JSON validation failed for $jsonFile"
}

Write-Host "Smoke test passed - exit code $exit, file $jsonFile"
exit 0
