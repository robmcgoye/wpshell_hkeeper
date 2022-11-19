Using module ".\clsApiKeys.psm1"

# enum frequency
# {
#   daily = 1
#   at_startup = 2
# }

class TaskScheduler
{
  [string]$name
  [string]$path
  [string]$action = "powershell.exe"
  [string]$action_arguments
  # [frequency]$frequency
  # [int]$interval
  [string]$user
  [string]$passwd

  TaskScheduler([string]$n, [string]$p, [string]$sch_args)
  {
    $this.name = $n
    $this.path = $p
    $this.action_arguments = $sch_args
    $api_keys = [ApiKeys]::new()
    $this.user = $api_keys.get_api_user()
    $this.passwd = $api_keys.get_api_user_pwd()
  }

  hidden [boolean]initialized()
  {
    $init = $false
    if ([string]::IsNullOrEmpty($this.user)) {
    } elseif ([string]::IsNullOrEmpty($this.passwd)) {
    } elseif ([string]::IsNullOrEmpty($this.name)) {
    } elseif ([string]::IsNullOrEmpty($this.path)) {
    } elseif ([string]::IsNullOrEmpty($this.action_arguments)) {
    } else {
      $init = $true
    }
    return $init
  }

  [Boolean]task_exists()
  {
    if(Get-ScheduledTask | Where-Object {($_.TaskPath -eq $this.path -and $_.TaskName -eq $this.name)}){
      return $true
    }else {
      return $false
    }
  }

  set_task_startup()
  {
    if ($this.initialized()) {
      $trigger = New-ScheduledTaskTrigger -AtStartup
      $taction = $this.get_task_action()
      $settings = New-ScheduledTaskSettingsSet
      if ($this.task_exists()) {
        set-ScheduledTask -TaskName $this.name -TaskPath $this.path -User $this.user -Password $this.passwd -Settings $settings -Action $taction -Trigger $trigger
      } else {
        Register-ScheduledTask -TaskName $this.name -TaskPath $this.path -User $this.user -Password $this.passwd -Settings $settings -Action $taction -Trigger $trigger
      }
    }
  }

  hidden [CimInstance]get_task_action()
  {
    return New-ScheduledTaskAction -Execute $this.action -Argument $this.action_arguments
  }

  set_daily_task([int]$interval, [string]$time)
  {
    if ($this.initialized()) {
      $trigger = New-ScheduledTaskTrigger -Daily -At $time -RepetitionInterval $interval
      $taction = $this.get_task_action()
      $settings = New-ScheduledTaskSettingsSet
      if ($this.task_exists()) {
        set-ScheduledTask -TaskName $this.name -TaskPath $this.path -User $this.user -Password $this.passwd -Settings $settings -Action $taction -Trigger $trigger
      } else {
        Register-ScheduledTask -TaskName $this.name -TaskPath $this.path -User $this.user -Password $this.passwd -Settings $settings -Action $taction -Trigger $trigger
      }
    }
  }

  remove_task()
  {
    if ($this.task_exists()) {
      Unregister-ScheduledTask -TaskName $this.name -TaskPath $this.path -Confirm:$false
    }
  }

}
