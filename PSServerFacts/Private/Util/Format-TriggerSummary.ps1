function Format-TriggerSummary {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Trigger)

    $type = $Trigger.CimClass.CimClassName
    $time = $null
    if ($Trigger.StartBoundary) {
        try { $time = ([datetime]$Trigger.StartBoundary).ToString('HH:mm') } catch {}
    }

    switch ($type) {
        'MSFT_TaskDailyTrigger'   { return "Daily at $time" }
        'MSFT_TaskTimeTrigger'    { return "Once at $time" }
        'MSFT_TaskBootTrigger'    { return 'At system startup' }
        'MSFT_TaskLogonTrigger'   {
            if ($Trigger.UserId) { return "At logon of $($Trigger.UserId)" } else { return 'At any user logon' }
        }
        'MSFT_TaskIdleTrigger'    { return 'When system is idle' }
        'MSFT_TaskWeeklyTrigger'  {
            $names = @('Sun','Mon','Tue','Wed','Thu','Fri','Sat')
            $bits  = [int]$Trigger.DaysOfWeek
            $days  = for ($i=0; $i -lt 7; $i++) { if ($bits -band (1 -shl $i)) { $names[$i] } }
            return "Weekly on $($days -join ', ') at $time"
        }
        default                   { return $type }
    }
}
