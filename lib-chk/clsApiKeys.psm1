class ApiKeys 
{
  [string]$hk_root_path = "HKLM:\SOFTWARE"
  [string]$hk_root_key = "ntr-tech.com"
	[string]$hk_user_key = "user"
	[string]$hk_password_key = "pwd"
	[string]$hk_api_key = "api_key"
	[string]$hk_key_key = "computer_key"
	[string]$hk_reboot = "needs_reboot"


  hidden [string]get_hk_path()
  {
    return "$($this.hk_root_path)\$($this.hk_root_key)"
  }

  [string]get_api_key()
  {
    $value = ConvertTo-SecureString ($this.get_key($this.hk_api_key))
    $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value))
    return $value
  }

  [string]get_api_user_pwd()
  {
    $value = ConvertTo-SecureString ($this.get_key($this.hk_password_key))
    $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value))
    return $value
  }

  [string]get_api_user()
  {
    return $this.get_key($this.hk_user_key)
  }

  set_reboot([boolean]$reboot)
  {
    if ($reboot) {
      $value = 1
    } else {
      $value = 0
    }
    if (-not($this.is_api_key($this.hk_reboot))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_reboot -Value $value
    } else {
      Set-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_reboot -Value $value
    }
  }

  [boolean]needs_reboot()
  {
    $reboot = $false
    $value = $this.get_key($this.hk_reboot)
    if (1 -eq $value) {
      $reboot = $true
    }
    return $reboot
  }

  [string]get_computer_key()
  {
    $value = ConvertTo-SecureString ($this.get_key($this.hk_key_key))
    $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($value))
    return $value
  }

  [boolean]update_key([securestring]$key)
  {
    $executed = $false
    if ($this.is_api_key($this.hk_key_key)) {
      Set-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_key_key -Value ($key | ConvertFrom-SecureString)
      $executed = $true
    }
    return $executed
  }

  [securestring]generate_key()
  {
    return (ConvertTo-SecureString (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | ForEach-Object {[char]$_})) -AsPlainText -Force) 
  }

  [Boolean]is_api_setup()
  {
    $user_key = $this.is_api_key($this.hk_user_key)
    $api_key = $this.is_api_key($this.hk_api_key)
    $pass_key = $this.is_api_key($this.hk_password_key)
    $key_key = $this.is_api_key($this.hk_key_key)
    return ($user_key -and $api_key -and $pass_key -and $key_key)
  }

  hidden [boolean]is_api_key([string]$key_name)
  {
    return ($null -ne (Get-ItemProperty -Path ($this.get_hk_path()) -Name $key_name -ErrorAction SilentlyContinue))
  }

  hidden [string]get_key([string]$key_name)
  {
    $value = $null
    if ($this.is_api_key($key_name)) {
      $value = Get-ItemPropertyValue -Path ($this.get_hk_path()) -Name $key_name
    }
    return $value
  }

  setup_api_keys([string]$user, [securestring]$password, [securestring]$api_key)
  {
    if ($null -eq (get-Item -Path ($this.get_hk_path()) -ErrorAction SilentlyContinue)) {
      new-Item -Path $this.hk_root_path -name $this.hk_root_key
    }
    if (-not($this.is_api_key($this.hk_user_key))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_user_key -Value $user -PropertyType "String"
    } else {
      Set-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_user_key -Value $user
    }
    if (-not($this.is_api_key($this.hk_password_key))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_password_key -Value ($password | ConvertFrom-SecureString) -PropertyType "String"
    } else {
      Set-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_password_key -Value ($password | ConvertFrom-SecureString)
    }
    if (-not($this.is_api_key($this.hk_api_key))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_api_key -Value ($api_key | ConvertFrom-SecureString) -PropertyType "String"
    } else {
      Set-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_api_key -Value ($api_key | ConvertFrom-SecureString)
    }
    if (-not($this.is_api_key($this.hk_key_key))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_key_key -Value (($this.generate_key()) | ConvertFrom-SecureString) -PropertyType "String"
    }
    if (-not($this.is_api_key($this.hk_reboot))) {
      New-ItemProperty -Path ($this.get_hk_path()) -Name $this.hk_reboot -Value 0 -PropertyType "dword"
    }
  }

  remove_api_keys()
  {
    if ($null -ne (get-Item -Path ($this.get_hk_path()) -ErrorAction SilentlyContinue)) {
      Remove-Item -Path ($this.get_hk_path()) -Force
    }
  }
}
