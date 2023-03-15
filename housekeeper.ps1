<#
    .SYNOPSIS
       script that interfaces with API to perform tasks on computer like running sfc /scan etc.

    .DESCRIPTION
        Script that interfaces with api to execute jobs set on admin console

    .PARAMETER setup
        set to true to setup api to execute

    .NOTES
        Name: housekeeper
        Author: Rob McGoye
        Version History:
#>
#requires -version 5.1
#Requires -RunAsAdministrator

Using module ".\lib-chk\clsApiKeys.psm1"
Using module ".\lib-chk\clsApiUrls.psm1"
Using module ".\lib-chk\clsComputers.psm1"
Using module ".\lib-chk\clsDiskCleanup.psm1"
Using module ".\lib-chk\clsFileSystemChecks.psm1"
Using module ".\lib-chk\clsJobs.psm1"
Using module ".\lib-chk\clsHardware.psm1"
Using module ".\lib-chk\clsLogging.psm1"
Using module ".\lib-chk\clsWebRequest.psm1"
Using module ".\lib-chk\clsTaskScheduler.psm1"
Using module ".\lib-chk\clsWindowsUpdate.psm1"

Param (
 [boolean]$setup = $false,
 [boolean]$on_startup = $false
 )

function set_constants()
{
  Set-Variable log_error -option Constant -value 1 -scope script
  Set-Variable log_warning -option Constant -value 2 -scope script
  Set-Variable log_info -option Constant -value 3 -scope script
  Set-Variable job_error -option Constant -value 2 -scope script
  Set-Variable job_warning -option Constant -value 1 -scope script
  Set-Variable job_info -option Constant -value 0 -scope script
  Set-Variable hk_build -option Constant -value 1 -scope script
}

function is_administrator() 
{
  return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function reboot_computer()
{
  $task_scheduler = [TaskScheduler]::new("$($script:prefs.task_name)_start", $script:prefs.task_path, "$($script:script_path_name) -on_startup `$true")
  $task_scheduler.set_task_startup()
  if ($script:prefs.reboot -eq 1) {
    Restart-Computer -force
  }
}

function clear_reboot()
{
  $task_scheduler = [TaskScheduler]::new("$($script:prefs.task_name)_start", $script:prefs.task_path, "$($script:script_path_name) -on_startup `$true")
  $task_scheduler.remove_task()
}

function install_updates([int]$job_id, [Jobs]$update_task, [Logging]$logger, [ApiKeys]$api)
{
  $update_modules_installed = $true
  $windows_update = [WindowsUpdates]::new()
  if (-not $windows_update.module_installed()) {
    if (-not $windows_update.install_module()) {
      [void]$update_task.create_event($logger, $job_id, $script:job_error, "Error installing the windows update module. Check event viewer.")
      $update_modules_installed = $false
    }
  }
  if ($update_modules_installed) {
    if (($windows_update.updates_to_install()) -and (-not $windows_update.reboot_status())) {
      if ($windows_update.install_updates()) {
        if ($windows_update.reboot_status()) {
          [void]$update_task.create_event($logger, $job_id, $script:job_warning, "Installed windows updates but computer needs to be rebooted.")
          $api.set_reboot($true)
        } else {
          [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully installed windows updates.")    
          [void]$update_task.mark_completed($logger, $job_id)    
        }
      }
    } elseif ($windows_update.reboot_status()) {
      [void]$update_task.create_event($logger, $job_id, $script:job_warning, "Need to reboot computer to install updates.")
      $api.set_reboot($true)
    } else {
      [void]$update_task.create_event($logger, $job_id, $script:job_info, "No updates to install. All updates have already been installed.")
      [void]$update_task.mark_completed($logger, $job_id)
    }      
  }
}

function delete_temp_files([int]$job_id, [Jobs]$update_task, [Logging]$logger)
{
  $disk_cleanup = [DiskCleanup]::new($logger)
  $disk_cleanup.delete_temporary_files()
  if (-not $disk_cleanup.any_errors($true)) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully deleted temp files.")
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_warning, "Error deleting temp files. Check event viewer.")
  }
  [void]$update_task.mark_completed($logger, $job_id)
}

function optimize_drives([int]$job_id, [Jobs]$update_task, [Logging]$logger)
{
  $fsc = [FileSystemChecks]::new($logger)
  if ($fsc.optimize_drives()) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully optimized all of the drives in the system.")
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_error, "Optimization incountered some error(s) check event viewer.")
  }
  [void]$update_task.mark_completed($logger, $job_id)
  $fsc = $null  
}

function rebuild_indexes([int]$job_id, [Jobs]$update_task, [Logging]$logger)
{
  $disk_cleanup = [DiskCleanup]::new($logger)
  $disk_cleanup.rebuild_windows_indexes()
  if (-not $disk_cleanup.any_errors($true)) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully rebuilt the windows indexes.")
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_error, "Error rebuiling the windows indexes. Check event viewer.")
  }
  [void]$update_task.mark_completed($logger, $job_id)
}

function repair_image( [int]$job_id, [Jobs]$update_task, [Logging]$logger, [ApiKeys]$api )
{
  $fsc = [FileSystemChecks]::new($logger)
  $result = $fsc.cleanup_windows_image()
  if ($result -eq 0) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully updated the windows image.")
  } elseif ($result -eq 1) {
    [void]$update_task.create_event($logger, $job_id, $script:job_warning, "Sucessfully repaired the windows image.")
    $api.set_reboot($true)
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_error, "Errors check event viewer trying to repair the windows image.")
  }
  [void]$update_task.mark_completed($logger, $job_id)
  $fsc = $null
}

function sfc_scan([int]$job_id, [Jobs]$update_task, [Logging]$logger, [ApiKeys]$api) 
{
  $fsc = [FileSystemChecks]::new($logger)
  if ($fsc.run_sfc_scan()) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully executed SFC scan. (No integrity violations)")
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_error, "SFC scan had errors check event viewer.")
    $api.set_reboot($true)
  }
  [void]$update_task.mark_completed($logger, $job_id)
  $fsc = $null  
}

function check_disk([int]$job_id, [Jobs]$update_task, [Logging]$logger, [ApiKeys]$api)
{
  $fsc = [FileSystemChecks]::new($logger)
  if (-not $fsc.check_disk()) {
    [void]$update_task.create_event($logger, $job_id, $script:job_info, "Successfully executed check disk.")
  } else {
    [void]$update_task.create_event($logger, $job_id, $script:job_error, "Check Disk found errors and scheduled a repair.")
    $api.set_reboot($true)
  }
  [void]$update_task.mark_completed($logger, $job_id)
  $fsc = $null  
}

# initialize vars to be used
# --------------------------------------------------------
set_constants
$script:script_path_name =$MyInvocation.MyCommand.Path
Import-LocalizedData -BindingVariable prefs -FileName housekeeper.psd1
$event_logger = [Logging]::new($script:prefs.evt_log_folder, $script:prefs.evt_log_source)
$api_key = [ApiKeys]::new()
$computer = [Computers]::new($prefs.api_url)
# --------------------------------------------------------
if (-not(is_administrator)) {
    Write-Host "ERROR: This script needs to be executed with administrator privileges"
    $event_logger.write_event($script:log_error, 101, "ERROR: Not an administrator!")  
} else {
  # ------------------------------------------------------
  # make sure that api is configured or set to setup api
  # ------------------------------------------------------
  if ((-not($api_key.is_api_setup())) -and ($setup -eq $false)) {
    # need to execute this from the console to setup api
    $event_logger.write_event($script:log_error, 101, "ERROR: The API is not configured yet. Please execute from the console and use the setup switch to setup API")
  } else {
    # check to see if startup flag is set
    if ($on_startup) {
      $api_key.set_reboot($false)
      clear_reboot
    }
    # ------------------------------------------------------
    if ($setup) {
      if (-not($api_key.is_api_setup())) {
        $user = whoami
        $password = Read-Host "Enter password for user: ${user} " -AsSecureString
        $clientkey = Read-Host "Enter the client API key " | ConvertTo-SecureString -AsPlainText -Force
        $computerkey = Read-Host "Enter the computer key (blank for new computer) " | ConvertTo-SecureString -AsPlainText -Force -ErrorAction SilentlyContinue
        if ([string]::IsNullOrEmpty($computerkey))
        {
          $comp_rec = $computer.new_computer($user, $clientkey, $password, $event_logger)
          if ($null -eq $comp_rec) {
            $api_key.remove_api_keys()
            $event_logger.write_event($script:log_error, 101, "ERROR: unable to create record so api not created.")
            write-output "Couldn't create record on server. Check the event logs."
          }    
        } else {
          $api_key.rebuild_api_keys($user, $password, $clientkey, $computerkey)
        }       
      } else {
        write-output "Already configured!"
      }
      if ($api_key.is_api_setup()) {
        if ((Read-Host -Prompt "Do you want to schedule this to run daily? (y/n)") -eq "y") { 
          $interval = Read-Host -Prompt "Enter the days to wait before executing (1)"
          $scheduled_time = Read-Host -Prompt "Enter the time to execute script (12AM)"
          $task_scheduler = [TaskScheduler]::new($Prefs.task_name, $Prefs.task_path, $script:script_path_name)
          $task_scheduler.set_daily_task($interval, $scheduled_time) 
        }
      }
    }
    # ------------------------------------------------------
    if ($api_key.is_api_setup()) {
      # ------------------------------------------------------
      # load the computer record from the server.
      # ------------------------------------------------------
      if ($null -eq $comp_rec) {
        $computer.set_token_key(($api_key.get_api_key()), ($api_key.get_computer_key()))
        $comp_rec = $computer.get_computer_by_key($event_logger)
      }
      # ------------------------------------------------------
      if ($null -ne $comp_rec) {
        # ------------------------------------------------------
        # Get a list of jobs to execute
        # ------------------------------------------------------
        $task = [Jobs]::new($prefs.api_url, $api_key.get_api_key())
        $jobs = $task.get_jobs($event_logger, $comp_rec.id)
        # ------------------------------------------------------
        foreach ($job in $jobs) {
          if (-not($api_key.needs_reboot())) {
            switch($job.action) {
              # -------------------
              "install_updates" {
                install_updates -job_id $job.id -update_task $task -logger $event_logger -api $api_key
              }
              # -------------------
              "delete_temp_files" {
                delete_temp_files -job_id $job.id -update_task $task -logger $event_logger
              }
              # -------------------
              "optimize_volumes" {
                optimize_drives -job_id $job.id -update_task $task -logger $event_logger
              }
              # -------------------
              "rebuild_indexes" {
                rebuild_indexes -job_id $job.id -update_task $task -logger $event_logger
              }
              # -------------------
              "repair_image" {
                repair_image -job_id $job.id -update_task $task -logger $event_logger -api $api_key
              }
              # -------------------
              "sfc_scan" {
                sfc_scan -job_id $job.id -update_task $task -logger $event_logger -api $api_key
              }
              # -------------------
              "check_disk" {
                check_disk -job_id $job.id -update_task $task -logger $event_logger -api $api_key
              }
              # -------------------
              "update_computer" {
                if (-not $null -eq $computer.update_computer($event_logger, $comp_rec.id)) {
                  [void]$task.create_event($event_logger, $job.id, $script:job_info, "Successfully updated the computer.")
                  [void]$task.mark_completed($event_logger, $job.id)
                } else {
                  [void]$task.create_event($event_logger, $job.id, $script:job_error, "Errors check event viewer Unable to update the computer.")
                }
              }              
              # -------------------
              default { 
                $event_logger.write_event($script:log_error, 110, "ERROR: this job ${job.action} not configured!")
              }
              # -------------------
            }
          } else {
            break
          }
        }
        if ($api_key.needs_reboot()) {
          reboot_computer
        }
      }
    } else {
      $event_logger.write_event($script:log_error, 101, "ERROR: unable to load the computer record.")
    }
  }
} 
