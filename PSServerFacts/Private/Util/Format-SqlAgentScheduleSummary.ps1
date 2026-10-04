function Format-SqlAgentScheduleSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Schedule)

    # SMO JobSchedule (from $job.JobSchedules) exposes enum properties with names that
    # differ from dbatools' Get-DbaAgentSchedule aliases:
    #   FrequencyType  ↔ FrequencyTypes  (plural in SMO)
    #   FrequencySubdayType  ↔ FrequencySubDayTypes  (plural + capital D in SMO)
    #   FrequencySubdayInterval  ↔ FrequencySubDayInterval  (capital D in SMO)
    #   FrequencyRelativeInterval  ↔ FrequencyRelativeIntervals  (plural in SMO)
    # Read the dbatools singular alias first, fall back to the SMO plural form.
    $prop = {
        param($obj, [string[]]$names)
        foreach ($n in $names) {
            if ($obj.PSObject.Properties[$n]) {
                $v = $obj.$n
                if ($null -ne $v -and "$v" -ne '') { return $v }
            }
        }
        $null
    }

    $type             = [string](& $prop $Schedule 'FrequencyType','FrequencyTypes')
    $subdayType       = [string](& $prop $Schedule 'FrequencySubdayType','FrequencySubDayTypes')
    $subdayInterval   = [int]   (& $prop $Schedule 'FrequencySubdayInterval','FrequencySubDayInterval')
    $relativeInterval = [string](& $prop $Schedule 'FrequencyRelativeInterval','FrequencyRelativeIntervals')

    $time = if ($Schedule.ActiveStartTimeOfDay) { ([timespan]$Schedule.ActiveStartTimeOfDay).ToString('hh\:mm') } else { '00:00' }

    switch ($type) {
        'OneTime' {
            $date = if ($Schedule.ActiveStartDate) { ([datetime]$Schedule.ActiveStartDate).ToString('yyyy-MM-dd') } else { '?' }
            return "One-time at $date $time"
        }
        'Daily' {
            if ($subdayType -in 'Minute','Second','Hour' -and $subdayInterval -gt 0) {
                $unit  = switch ($subdayType) { 'Minute' { 'min' } 'Second' { 'sec' } 'Hour' { 'hr' } }
                $start = if ($Schedule.ActiveStartTimeOfDay) { ([timespan]$Schedule.ActiveStartTimeOfDay).ToString('hh\:mm') } else { '00:00' }
                $end   = if ($Schedule.ActiveEndTimeOfDay)   { ([timespan]$Schedule.ActiveEndTimeOfDay).ToString('hh\:mm')   } else { '23:59' }
                return "Every $subdayInterval $unit from $start to $end"
            }
            return "Daily at $time"
        }
        'Weekly' {
            $names = @('Sun','Mon','Tue','Wed','Thu','Fri','Sat')
            # SQL Agent stores weekly bitmask in FrequencyInterval: Sun=1,Mon=2,Tue=4,Wed=8,Thu=16,Fri=32,Sat=64
            $bits = [int]$Schedule.FrequencyInterval
            $days = for ($i=0; $i -lt 7; $i++) { if ($bits -band (1 -shl $i)) { $names[$i] } }
            return "Weekly $($days -join ', ') at $time"
        }
        'MonthlyRelative' {
            # Index corresponds to SQL Agent FrequencyInterval value for day-of-week specifier
            # 1=Sun,2=Mon,3=Tue,4=Wed,5=Thu,6=Fri,7=Sat,8=Day,9=Weekday,10=WeekendDay
            $names = @('?','Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Day','Weekday','WeekendDay')
            $idx   = [int]$Schedule.FrequencyInterval
            $day   = if ($idx -ge 1 -and $idx -le 10) { $names[$idx] } else { 'Day' }
            return "$relativeInterval $day at $time"
        }
        'Monthly' {
            return "Day $([int]$Schedule.FrequencyInterval) of month at $time"
        }
        'AutoStart' { return 'On SQL Agent startup' }
        'OnIdle'    { return 'When CPU idle' }
        default     { return "$type (raw)" }
    }
}
