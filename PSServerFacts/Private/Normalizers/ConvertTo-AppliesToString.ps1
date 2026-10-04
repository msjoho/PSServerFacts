function ConvertTo-AppliesToString {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$InheritanceFlags,
        [Parameter(Mandatory)][string]$PropagationFlags
    )
    $i = $InheritanceFlags -replace '\s',''
    $p = $PropagationFlags -replace '\s',''

    $hasC = $i -match 'ContainerInherit'
    $hasO = $i -match 'ObjectInherit'
    $isInheritOnly = $p -match 'InheritOnly'

    if (-not $hasC -and -not $hasO) { return 'ThisFolderOnly' }
    if ($hasC -and $hasO -and $isInheritOnly)     { return 'SubfoldersAndFilesOnly' }
    if ($hasC -and $hasO -and -not $isInheritOnly){ return 'ThisFolderSubfoldersAndFiles' }
    if ($hasC -and -not $hasO -and $isInheritOnly){ return 'SubfoldersOnly' }
    if ($hasC -and -not $hasO)                    { return 'ThisFolderAndSubfolders' }
    if ($hasO -and -not $hasC -and $isInheritOnly){ return 'FilesOnly' }
    if ($hasO -and -not $hasC)                    { return 'ThisFolderAndFiles' }
    return "$InheritanceFlags / $PropagationFlags"
}
