. $PSScriptRoot/Bootstrap.ps1

Describe 'Format-SqlAgentScheduleSummary' {
    It 'formats OneTime' {
        $s = [pscustomobject]@{ FrequencyType = 'OneTime'; ActiveStartTimeOfDay = [timespan]'02:00:00'; ActiveStartDate = [datetime]'2026-05-15' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'One-time at 2026-05-15 02:00'
    }
    It 'formats Daily, interval 1' {
        $s = [pscustomobject]@{ FrequencyType = 'Daily'; FrequencyInterval = 1; ActiveStartTimeOfDay = [timespan]'02:00:00'; FrequencySubdayType = 'Once' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'Daily at 02:00'
    }
    It 'formats Daily subday-minutes 15 between 09:00 and 17:00' {
        $s = [pscustomobject]@{ FrequencyType='Daily'; FrequencyInterval=1; FrequencySubdayType='Minute'; FrequencySubdayInterval=15; ActiveStartTimeOfDay=[timespan]'09:00:00'; ActiveEndTimeOfDay=[timespan]'17:00:00' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'Every 15 min from 09:00 to 17:00'
    }
    It 'formats Weekly Mon+Wed' {
        # Mon=2 + Wed=8 = 10
        $s = [pscustomobject]@{ FrequencyType='Weekly'; FrequencyInterval=10; ActiveStartTimeOfDay=[timespan]'06:30:00'; FrequencySubdayType='Once' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'Weekly Mon, Wed at 06:30'
    }
    It 'formats MonthlyRelative first Monday' {
        # FrequencyRelativeInterval First=1, DaysOfWeek=2 (Mon)
        $s = [pscustomobject]@{ FrequencyType='MonthlyRelative'; FrequencyRelativeInterval='First'; FrequencyInterval=2; ActiveStartTimeOfDay=[timespan]'03:00:00' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'First Monday at 03:00'
    }
    It 'formats Monthly day-of-month 15' {
        $s = [pscustomobject]@{ FrequencyType='Monthly'; FrequencyInterval=15; ActiveStartTimeOfDay=[timespan]'04:00:00'; FrequencySubdayType='Once' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'Day 15 of month at 04:00'
    }
    It 'formats AutoStart' {
        $s = [pscustomobject]@{ FrequencyType='AutoStart' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'On SQL Agent startup'
    }
    It 'formats OnIdle' {
        $s = [pscustomobject]@{ FrequencyType='OnIdle' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'When CPU idle'
    }
    It 'falls back to FrequencyType for unknown' {
        $s = [pscustomobject]@{ FrequencyType='Mystery' }
        Format-SqlAgentScheduleSummary -Schedule $s | Should -Be 'Mystery (raw)'
    }
}
