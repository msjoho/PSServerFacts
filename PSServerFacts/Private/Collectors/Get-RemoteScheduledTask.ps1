function Get-RemoteScheduledTask {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        Get-ScheduledTask | ForEach-Object {
            $task = $_
            $actions = @($task.Actions | ForEach-Object {
                [pscustomobject]@{ Execute = $_.Execute; Arguments = $_.Arguments }
            })
            [pscustomobject]@{
                TaskPath = $task.TaskPath
                TaskName = $task.TaskName
                State    = [string]$task.State
                RunAs    = $task.Principal.UserId
                Triggers = @($task.Triggers)
                Actions  = $actions
            }
        }
    } | Select-Object TaskPath, TaskName, State, RunAs, Triggers, Actions
}
