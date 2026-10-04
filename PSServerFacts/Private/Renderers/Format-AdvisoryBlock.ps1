function Format-AdvisorySummaryBlock {
    # Returns the top-of-report '## Advisories' markdown block, or empty string
    # when no advisories. Caller (ConvertTo-ServerFactsMarkdown) decides where to
    # place it. Advisories must already be sorted (Critical->Warning->Note, then
    # Section, then Rule) -- this function does not re-sort.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Advisories)

    if (@($Advisories).Count -eq 0) { return '' }

    $countCritical = @($Advisories | Where-Object Severity -eq 'Critical').Count
    $countWarning  = @($Advisories | Where-Object Severity -eq 'Warning').Count
    $countNote     = @($Advisories | Where-Object Severity -eq 'Note').Count

    $countText = @(
        if ($countCritical -gt 0) { "$countCritical critical" }
        if ($countWarning  -gt 0) { "$countWarning warning"  + $(if ($countWarning -gt 1) {'s'} else {''}) }
        if ($countNote     -gt 0) { "$countNote note"        + $(if ($countNote    -gt 1) {'s'} else {''}) }
    ) -join ', '

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## Advisories *($countText)*")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Severity | Section | Rule | Message |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($a in $Advisories) {
        $glyph = switch ($a.Severity) {
            'Critical' { [System.Char]::ConvertFromUtf32(0x1F6D1) }
            'Warning'  { -join @([char]0x26A0,[char]0xFE0F) }
            'Note'     { -join @([char]0x2139,[char]0xFE0F) }
            default    { '' }
        }
        [void]$sb.AppendLine("| $glyph $($a.Severity) | $($a.Section) | $($a.Rule) | $($a.Message) |")
    }
    $sb.ToString().TrimEnd()
}

function Format-AdvisoryInlineLine {
    # Returns one blockquote line for inline rendering at the end of a section.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Advisory)

    $glyph = switch ($Advisory.Severity) {
        'Critical' { [System.Char]::ConvertFromUtf32(0x1F6D1) }
        'Warning'  { -join @([char]0x26A0,[char]0xFE0F) }
        'Note'     { -join @([char]0x2139,[char]0xFE0F) }
        default    { '' }
    }
    "> $glyph **$($Advisory.Rule)** — $($Advisory.Message)"
}
