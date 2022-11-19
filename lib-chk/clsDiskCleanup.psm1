Using module ".\clsLogging.psm1"

class DiskCleanup 
{
  [Logging]$event_logger
  [bool]$errors_logged

  DiskCleanup([Logging]$e)
  {
    $this.event_logger = $e
    $this.errors_logged = $false
  }

  delete_temporary_files()
  {
    # $this.event_logger.write_event(1, 104, "Trying to delete temporary file(s) ")
    Get-ChildItem "$($ENV:SystemDrive)\Users" | ForEach-Object {
      $base = "$($ENV:SystemDrive)\Users\$($_.Name)"
      $firefox_path = "$($base)\AppData\Local\Mozilla\Firefox\Profiles\*.default*" 
      $this.delete_files("$($firefox_path)\cache\*")
      $this.delete_files("$($firefox_path)\cache2\entries\*")
      $this.delete_files("$($firefox_path)\thumbnails\*")
      $this.delete_files("$($firefox_path)\cookies.sqlite")
      $this.delete_files("$($firefox_path)\webappsstore.sqlite")
      $this.delete_files("$($firefox_path)\chromeappsstore.sqlite")
      $chrome_path = "$($base)\AppData\Local\Google\Chrome\User Data\Default"
      $this.delete_files("$($chrome_path)\Cache\*")
      $this.delete_files("$($chrome_path)\Code Cache\js\*")
      # $this.delete_files("$($chrome_path)\Cache2\entries\*")
      # $this.delete_files("$($chrome_path)\Cookies")
      $this.delete_files("$($chrome_path)\Network\Cookies")
      # $this.delete_files("$($chrome_path)\Media Cache")
      # $this.delete_files("$($chrome_path)\Cookies-Journal")
      $this.delete_files("$($chrome_path)\Network\Cookies-Journal")
      # $this.delete_files("$($chrome_path)\ChromeDWriteFontCache")
      $edge_path = "$($base)\AppData\Local\Microsoft\Edge\User Data\Default"
      $this.delete_files("$($edge_path)\Cache\*")
      $this.delete_files("$($edge_path)\Code Cache\js\*")
      $this.delete_files("$($edge_path)\Network\Cookies")
      # $this.delete_files("$($edge_path)\Media Cache")
      $this.delete_files("$($edge_path)\Network\Cookies-Journal")
      $ms_path = "$($base)\AppData\Local"
      $this.delete_files("$($ms_path)\Microsoft\Windows\Temporary Internet Files\*")
      $this.delete_files("$($ms_path)\Microsoft\Windows\WER\*")
      $this.delete_files("$($ms_path)\Microsoft\Temp\*")            
    }
    $this.delete_files("$($ENV:windir)\Temp\*")
    $this.delete_files("$($ENV:windir)\Prefetch\*")
    $this.delete_files("$($ENV:windir)\`$recycle.bin\")
  }

  rebuild_windows_indexes()
  {
    $start_svc = $false
    $indexing_svc = get-service -name wsearch -ErrorAction SilentlyContinue
    if ($null -ne $indexing_svc) {
      if ($indexing_svc.status -ne "Stopped") {
        $start_svc = $true
        stop-service -name wsearch
      }
      $this.delete_files("$($ENV:ProgramData)\Microsoft\Search\Data\Applications\Windows\Windows.edb")
      if ($start_svc) {
        start-service -name wsearch
      }
    }    
  }

  [bool]any_errors([bool]$reset = $true)
  {
    $errors = $this.errors_logged
    if ($reset) {
      $this.errors_logged = $false
    }
    return $errors
  }

  hidden [void]delete_files([string]$path)
  {
    if (test-path -path $path) {
      try 
      {
        Remove-Item -path $path -Recurse -Force -ErrorAction Stop
      }
      catch 
      {
        $this.event_logger.write_event(3, 104, "ERROR: $($_) ")
        $this.errors_logged = $true
      }
    }
  }
}
