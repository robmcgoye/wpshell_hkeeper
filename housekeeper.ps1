<#
    .SYNOPSIS
       script that interfaces with API to perform tasks on computer like running sfc /scan etc.

    .DESCRIPTION
        Script that interfaces with api to execute jobs set on admin console

    .PARAMETER install
        set to true to setup api to execute

    .NOTES
        Name: housekeeper
        Author: Rob McGoye
        Version History:
#>
#requires -version 5.1
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
 [boolean]$install = $false,
 [boolean]$on_startup = $false
 )

function is_administrator() 
{
  return ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}
function reboot_computer()
{
  $task_scheduler = [TaskScheduler]::new("$($Prefs.task_name)_start", $Prefs.task_path, "$($script:script_path_name) -on_startup `$true")
  $task_scheduler.set_task_startup()
  Restart-Computer -force
}
function clear_reboot()
{
  $task_scheduler = [TaskScheduler]::new("$($Prefs.task_name)_start", $Prefs.task_path, "$($script:script_path_name) -on_startup `$true")
  $task_scheduler.remove_task()
}

$script:script_path_name =$MyInvocation.MyCommand.Path
Import-LocalizedData -BindingVariable prefs -FileName housekeeper.psd1
if (-not(is_administrator)) {
    Write-Host "ERROR: This script needs to be executed with administrator privileges"
} else {
  $event_logger = [Logging]::new($prefs.evt_log_folder, $prefs.evt_log_source)
  $api_key = [ApiKeys]::new()
  if ((-not($api_key.is_api_setup())) -and ($install -eq $false)) {
    # need to execute this from the console to setup api
    $event_logger.write_event(1, 101, "ERROR: The API is not configured yet. Please execute from the console and use the install switch to setup API")
  } else {
    if ($on_startup) {
      $api_key.set_reboot($false)
      clear_reboot
    }
    $computer = [Computers]::new($prefs.api_url)
    if ($install) {
      if (-not($api_key.is_api_setup())) {
        $user = whoami
        $password = Read-Host "Enter password for user: ${user} " -AsSecureString
        $clientkey = Read-Host "Enter the client API key " | ConvertTo-SecureString -AsPlainText -Force
        $comp_rec = $computer.new_computer($user, $clientkey, $password, $event_logger)
        if ($null -eq $comp_rec) {
          $api_key.remove_api_keys()
        }  
      } else {
        write-output "Already installed!"
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
    if ($api_key.is_api_setup()) {
      if ($null -eq $comp_rec) {
        $computer.set_token_key(($api_key.get_api_key()), ($api_key.get_computer_key()))
        $comp_rec = $computer.get_computer_by_key($event_logger)
      }
      if ($null -ne $comp_rec) {
        # Get a list of jobs to execute
        $task = [Jobs]::new($prefs.api_url, $api_key.get_api_key())
        $jobs = $task.get_jobs($event_logger, $comp_rec.id)
        foreach ($job in $jobs) {
          switch($job.action) {
            # -------------------
            "install_updates" {
              $windows_update = [WindowsUpdates]::new()
              if (-not $windows_update.module_installed()) {
                if (-not $windows_update.install_module()) {
                  [void]$task.create_event($event_logger, $job.id, 1, "Error installing the windows update module. Check event viewer.")
                  break
                }
              }
              if (($windows_update.updates_to_install()) -and (-not $windows_update.reboot_status())) {
                if ($windows_update.install_updates()) {
                  if ($windows_update.reboot_status()) {
                    # log and reboot?
                    [void]$task.create_event($event_logger, $job.id, 0, "Installed windows updates but computer needs to be rebooted.")
                    $api_key.set_reboot($true)
                    reboot_computer
                  } else {
                    [void]$task.create_event($event_logger, $job.id, 0, "Successfully installed windows updates.")    
                    [void]$task.mark_completed($event_logger, $job.id)    
                  }
                }
              } elseif ($windows_update.reboot_status()) {
                [void]$task.create_event($event_logger, $job.id, 0, "Need to reboot computer to install updates.")
                $api_key.set_reboot($true)
                reboot_computer
              } else {
                [void]$task.create_event($event_logger, $job.id, 0, "No updates to install. All updates have already been installed.")
                [void]$task.mark_completed($event_logger, $job.id)
              }
            }
            # -------------------
            "delete_temp_files" {
              $disk_cleanup = [DiskCleanup]::new($event_logger)
              $disk_cleanup.delete_temporary_files()
              if (-not $disk_cleanup.any_errors($true)) {
                [void]$task.create_event($event_logger, $job.id, 0, "Successfully deleted temp files.")
              } else {
                [void]$task.create_event($event_logger, $job.id, 1, "Error deleting temp files. Check event viewer.")
              }
              [void]$task.mark_completed($event_logger, $job.id)
            }
            # -------------------
            "optimize_volumes" {
              $fsc = [FileSystemChecks]::new($event_logger)
              if ($fsc.optimize_drives()) {
                [void]$task.create_event($event_logger, $job.id, 0, "Successfully optimized all of the drives in the system.")
              } else {
                [void]$task.create_event($event_logger, $job.id, 1, "Optimization incountered some error(s) check event viewer.")
              }
              [void]$task.mark_completed($event_logger, $job.id)
              $fsc = $null
            }
            # -------------------
            "rebuild_indexes" {
              $disk_cleanup = [DiskCleanup]::new($event_logger)
              $disk_cleanup.rebuild_windows_indexes()
              if (-not $disk_cleanup.any_errors($true)) {
                [void]$task.create_event($event_logger, $job.id, 0, "Successfully rebuilt the windows indexes.")
              } else {
                [void]$task.create_event($event_logger, $job.id, 1, "Error rebuiling the windows indexes. Check event viewer.")
              }
              [void]$task.mark_completed($event_logger, $job.id)
            }
            # -------------------
            "update_computer" {
              if (-not $null -eq $computer.update_computer($event_logger, $comp_rec.id)) {
                if ($task.create_event($event_logger, $job.id, 0, "Successfully updated the computer.")) {
                  [void]$task.mark_completed($event_logger, $job.id)
                }                
              } else {
                [void]$task.create_event($event_logger, $job.id, 1, "Errors check event viewer Unable to update the computer.")
              }
            }
            # -------------------
            "repair_image" {
              if (-not($api_key.needs_reboot())) {
                $fsc = [FileSystemChecks]::new($event_logger)
                $result = $fsc.cleanup_windows_image()
                if ($result -eq 0) {
                  if ($task.create_event($event_logger, $job.id, 0, "Successfully updated the windows image.")) {
                    [void]$task.mark_completed($event_logger, $job.id)
                  }  
                } elseif ($result -eq 1) {
                  [void]$task.create_event($event_logger, $job.id, 1, "Sucessfully repaired the windows image.")
                  # reboot computer?
                  $api_key.set_reboot($true)
                  reboot_computer
                } else {
                  [void]$task.create_event($event_logger, $job.id, 1, "Errors check event viewer trying to repair the windows image.")
                }
                $fsc = $null
              }
            }
            # -------------------
            "sfc_scan" {
              if (-not($api_key.needs_reboot())) {
                $fsc = [FileSystemChecks]::new($event_logger)
                if ($fsc.run_sfc_scan()) {
                  if ($task.create_event($event_logger, $job.id, 0, "Successfully executed SFC scan. (No integrity violations)")) {
                    [void]$task.mark_completed($event_logger, $job.id)
                  }  
                } else {
                  [void]$task.create_event($event_logger, $job.id, 1, "SFC scan had errors check event viewer.")
                  $api_key.set_reboot($true)
                  reboot_computer
                }
              $fsc = $null
              }
            }
            # -------------------
            "check_disk" {
              if (-not($api_key.needs_reboot())) {
                $fsc = [FileSystemChecks]::new($event_logger)
                if (-not $fsc.check_disk()) {
                  [void]$task.create_event($event_logger, $job.id, 0, "Successfully executed check disk.")
                } else {
                  [void]$task.create_event($event_logger, $job.id, 1, "Check Disk found errors and scheduled a repair.")
                  $api_key.set_reboot($true)
                  reboot_computer
                }
                [void]$task.mark_completed($event_logger, $job.id)
                $fsc = $null
              }
            }
            # -------------------
            default { 
              $event_logger.write_event(1, 110, "ERROR: this job ${job.action} not configured!")
            }
            # -------------------
          }
        }
      }
    } else {
      $event_logger.write_event(1, 101, "ERROR: The API failed to get setup")
    }
  }
} 
