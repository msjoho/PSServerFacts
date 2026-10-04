function Test-IsDefaultScheduledTask {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$TaskPath,
        [Parameter(Mandatory)][string[]]$Patterns
    )
    foreach ($pattern in $Patterns) {
        if ($TaskPath -like $pattern) { return $true }
    }
    return $false
}
