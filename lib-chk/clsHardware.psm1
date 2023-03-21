class PcHardware 
{
  [string]$name
  [string]$manufacturer
  [string]$model
  [string]$os
  [string]$cpu
  [string]$serial_number
  [string]$mb_serial_number
  [string]$bios_released_on
  
  PcHardware() 
  {
    $systemInfo = Systeminfo
    $this.name = $env:COMPUTERNAME
    $this.manufacturer = ($systemInfo |Select-String '^System Manufacturer:').ToString().Split(':')[1].Trim()
    $this.model = ($systemInfo | Select-String '^System Model:').ToString().Split(':')[1].Trim()
    $this.os = ($systemInfo | Select-String '^OS Name:').ToString().Split(':')[1].Trim()
    $release_dts = Get-WmiObject Win32_bios | Select-object -expand ReleaseDate
    $this.bios_released_on = ([Management.ManagementDateTimeConverter]::ToDateTime($release_dts)).ToString('MM/dd/yyyy')
    $processor =  Get-wmiobject win32_processor | Select-object -expand name
    if ($processor -is [System.Array]) {
        $this.cpu = $processor[0]
    } else {
        $this.cpu = $processor
    }
    $this.serial_number = (wmic bios get serialnumber).Split("\n")[2].Trim()
    $this.mb_serial_number = (wmic baseboard get serialnumber).Split("\n")[2].Trim()
  }
  
}
 