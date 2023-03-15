# http://woshub.com/pswindowsupdate-module/
# Get-WUHistory -Last 10 | Where-Object { $_.result -ne "Succeeded" }
# [Net.ServicePointManager]::SecurityProtocol
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

class WindowsUpdates 
{
  [bool]reboot_status()
  {
    return Get-WURebootStatus -Silent
  }

  [bool]install_updates()
  {
    try
    {
      Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot
      return $true
    }
    catch
    {
      return $false
    }
  }

  [bool]updates_to_install()
  {
    if (Get-WUlist -MicrosoftUpdate) {
      return $true
    } else {
      return $false
    }
  }

  [bool]module_installed()
  {
    if ($null -eq (Get-Package -Name PSWindowsUpdate -ErrorAction SilentlyContinue)) {
      return $false
    } else {
      return $true
    }
  }

  [bool]install_module()
  {
    try
    {
      if(-not(Get-PackageProvider | Where-Object{$_.name -eq "NuGet"})){
        Install-PackageProvider -Name NuGet -Force
      }
      Install-Module -Name PSWindowsUpdate -Force
      return $true
    }
    catch
    {
      return $false
    }
  }
}