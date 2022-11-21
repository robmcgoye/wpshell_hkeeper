Using module ".\clsLogging.psm1"

class FileSystemChecks 
{
  [Logging]$event_logger
  [hashtable]$log_type = @{
    error = 1
    warning = 2
    info = 3
  }

  FileSystemChecks([Logging]$e)
  {
    $this.event_logger = $e
  }

  hidden [bool]execute_drive_optimization([string]$drive_letter, [string]$disk_type)
  {
    $finished = $true
    try
    {
      if ($disk_type -eq "SDD") {
        Optimize-Volume -DriveLetter $drive_letter -ReTrim -ErrorAction Stop
      } elseif ($disk_type -eq "HDD") {
        Optimize-Volume -DriveLetter $drive_letter -Defrag -ErrorAction Stop
      } else {
        $this.event_logger.write_event($this.log_type["warning"], 301, "Unknown disk type $($disk_type)")
        $finished = $false
      }
    }
    catch
    {
      $this.event_logger.write_event($this.log_type["error"], 301, "Error returned: $($_)")
      $finished = $false
    }
    return $finished
  }

  [bool]optimize_drives()
  {
    $issues = $false
    $disks = Get-PhysicalDisk
    foreach ($disk in $disks) {
      if ($disk.mediatype -eq "SDD") {
        $partitions = Get-Partition -DiskNumber $disk.DeviceId | Where-Object{ [char]$_.DriveLetter -ne 0 }
        foreach ($partition in $partitions) {
          if (-not $this.execute_drive_optimization($partition.DriveLetter, "SDD")) {
            $issues = $true
          }
        }
      } elseif ($disk.mediatype -eq "HDD") {
        $partitions = Get-Partition -DiskNumber $disk.DeviceId | Where-Object { [char]$_.DriveLetter -ne 0 }
        foreach ($partition in $partitions) {
          if (-not $this.execute_drive_optimization($partition.DriveLetter, "HDD")) {
            $issues = $true
          }
        }
      } else {
        $this.event_logger.write_event($this.log_type["warning"], 301, "MediaType not set to optimize drive")
        $issues = $true
      }
    }
    return $issues
  }

  [bool]check_disk()
  {
    $errors_found = $false
    $drives = Get-PSDrive | Where-Object {$_.Provider.name -eq 'FileSystem'}
    foreach ($drive in $drives) {
      $this.event_logger.write_event($this.log_type["info"], 301, "Checking drive: $($drive.name)")
      if ((Repair-Volume -DriveLetter $drive.name -Scan) -eq 'NoErrorsFound') {
        $errors_found = $true
        $this.event_logger.write_event($this.log_type["warning"], 201, "Scheduled offline repair on drive: $($drive.name)")
        Repair-Volume -DriveLetter $drive.name -OfflineScanAndFix
      }
    }
    return $errors_found
  }

  [int]cleanup_windows_image()
  {
    $this.event_logger.write_event($this.log_type["info"], 301, "Restoring windows image.")
    try
    {
      $result = Repair-WindowsImage -Online -RestoreHealth 
      if (-not(($result.ImageHealthState -eq 'Healthy'))) {
        $this.event_logger.write_event($this.log_type["error"], 402, "Issues with the image reapair ")
        $image_result = 2
      }elseif (-not($result.RestartNeeded)) {
        $this.event_logger.write_event($this.log_type["warning"], 201, "Need to reboot to finish the repair")
        $image_result = 1
      } else {
        $image_result = 0
      }
      return $image_result
    }
    catch 
    {
      $this.event_logger.write_event($this.log_type["error"], 104, "ERROR: $($_) ")
      return 3
    }
  }

  [boolean]run_sfc_scan()
  {
    $this.event_logger.write_event($this.log_type["info"],301, "Running SFC scan.")
    $result = $this.invoke_cmd( 'SFC-scan', "${env:Windir}\System32\sfc.exe", "/scannow" )
    # $result = Start-Process -FilePath "${env:Windir}\System32\sfc.exe" -ArgumentList '/scannow' -Wait -NoNewWindow
    $success_string = "Windows Resource Protection did not find any integrity violations"
    if ($result.stdout.contains($success_string)) {
      $this.event_logger.write_event($this.log_type["info"], 301, "SFC scan did not find any integrity violations.")
      return $true
    } else {
      $this.event_logger.write_event($this.log_type["warning"], 201, "SFC scan had issues with the reapir: $($result.stdout)")
      return $false
    }
  }

   hidden [pscustomobject]invoke_cmd ($commandTitle, $commandPath, $commandArguments) {
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $commandPath
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $commandArguments
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{
      commandTitle = $commandTitle
      stdout = $stdout
      stderr = $stderr
      ExitCode = $p.ExitCode
    }
  }
}

