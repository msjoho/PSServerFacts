function Test-JumphostPrerequisite {
    [CmdletBinding()]
    param(
        [switch]$SkipPSVersionCheck,
        [version]$PSVersion = $PSVersionTable.PSVersion
    )

    if (-not $SkipPSVersionCheck) {
        if ($PSVersion.Major -lt 7) {
            throw "Server assessment requires PowerShell 7+. Current: $PSVersion."
        }
    }
    foreach ($m in 'ActiveDirectory','NTFSSecurity') {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Required module '$m' is not installed on this jumphost."
        }
        Import-Module $m -ErrorAction Stop
    }
}
