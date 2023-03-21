Using module ".\clsApiKeys.psm1"
Using module ".\clsApiUrls.psm1"
Using module ".\clsHardware.psm1"
Using module ".\clsLogging.psm1"
Using module ".\clsWebRequest.psm1"

class Computers 
{
  [string]$token
  [string]$key
  [string]$api_base_url
  [hashtable]$log_type = @{
    error = 1
    warning = 2
    info = 3
  }

  Computers ([string]$url) 
  {
    $this.api_base_url = $url
  }

  hidden [bool]initialized()
  {
    $init = $false
    if (($null -ne $this.token) -and ($null -ne $this.api_base_url) -and ($null -ne $this.key)) {
      $init = $true
    }
    return $init
  }

  set_token_key([string]$t, [string]$k)
  {
    $this.token = $t
    $this.key = $k
  }

  [PSCustomObject]get_computer_by_key([Logging]$event_logger) 
  {
    $response = $null
    if ($null -ne $this.initialized()) {
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new($api_url.show_computer_by_key($this.key), ($api_url.get_auth_header($this.token)))
      $response = $api_request.get()
      if ($api_request.getstatus() -ne 200){
        $event_logger.write_event($this.log_type["error"], 104, "ERROR: the server returned this code $($api_request.getstatus()). The message was: $($response.message) `n the URL: $($api_url.show_computer_by_key($this.key))")
        $response = $null
      } else {
        $event_logger.write_event($this.log_type["info"], 200, "LOADED computer from the server")
      }    }
    return $response  
  }

  hidden [hashtable]build_computer_record()
  {
    $hardware = [PcHardware]::new()
    $record = @{
      "name" = $hardware.name;
      "manufacturer" = $hardware.manufacturer;
      "model" = $hardware.model;
      "operating_system" = $hardware.os;
      "cpu" = $hardware.cpu;
      "serial_number" = $hardware.serial_number;
      "mb_serial_number" = $hardware.mb_serial_number;
      "key" = $this.key;
      "bios_released_on" = $hardware.bios_released_on;
    }
    return @{ "computer" = $record }
}

  [PSCustomObject]update_computer([Logging]$event_logger, [int]$computer_id) 
  {
    $response = $null
    if (($null -ne $this.initialized()) -and (0 -lt $computer_id)) {
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new($api_url.update_computer($computer_id), ($api_url.get_auth_header($this.token)))
      $response = $api_request.patch($this.build_computer_record())
      if ($api_request.getstatus() -eq -1) {
        $event_logger.write_event($this.log_type["error"], 404, "ERROR ${response}.")
        $response = $null
      } elseif ($api_request.getstatus() -eq 422) {
        $event_logger.write_event($this.log_type["error"], 302, "Failed updating computer event. $($response.message)")
        $response = $null
      } elseif ($api_request.getstatus() -eq 200) {
        $event_logger.write_event($this.log_type["info"], 100, "Updated Computer -- $($api_request.getstatus()) response code.")
      } else {
        $event_logger.write_event($this.log_type["error"], 403, "ERROR server returned $($api_request.getstatus()) response code with the following message: $($response.message).")
        $response = $null
      }
   } else {
      $event_logger.write_event($this.log_type["error"], 101, "ERROR: jobs class not properly initialized")
    }
    return $response
  }

  [PSCustomObject]new_computer([string]$user, [securestring]$new_token, [securestring]$password, [Logging]$event_logger) 
  {
    $api_registry_keys = [ApiKeys]::new()
    $api_registry_keys.setup_api_keys($user, $password, $new_token)
    $this.set_token_key($api_registry_keys.get_api_key(), $api_registry_keys.get_computer_key())
    $event_logger.write_event(3, 300, "Added registry values needed for scheduled operations.")
    if (($null -ne $this.token) -and ($null -ne $this.key)) {
      $failed = $false
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new(($api_url.new_computer()), ($api_url.get_auth_header($this.token)))
      do {
        $response = $api_request.post($this.build_computer_record())
        if ($api_request.getstatus() -eq -1) {
          $event_logger.write_event($this.log_type["error"], 404, "ERROR ${response}.")
          $failed = $true
          $response = $null
        } elseif ($api_request.getstatus() -eq 422) {
          if ($null -ne ($response.message | get-member | Where-Object {$_.name -eq "key"})) {
            $event_logger.write_event($this.log_type["error"], 400, "This key is already being used.")
            $this.key = $api_registry_keys.generate_key()
            if ($api_registry_keys.update_key($this.key)) {
              # log change
              $event_logger.write_event($this.log_type["info"], 301, "Updated the computer key.")
            } else {
              $event_logger.write_event($this.log_type["error"], 401, "ERROR failed trying to update the computer key.")
              $failed = $true
              $response = $null
            }
          } else {
            $event_logger.write_event($this.log_type["error"], 302, "Failed validation of new computer. $($response.message)")
            $failed = $true
            $response = $null
          }
        } elseif ($api_request.getstatus() -eq 201) {
          # Do nothing since this is a positive response code :)
          $event_logger.write_event($this.log_type["info"], 301, "ADDED computer to the server.")
        } else {
          $event_logger.write_event($this.log_type["error"], 403, "ERROR server returned $($api_request.getstatus()) response code with the following message: $($response.message).")
          $failed = $true
          $response = $null
        }
      } until (($api_request.getstatus() -eq 201) -or ($failed))
    } else {
      $event_logger.write_event($this.log_type["error"], 200, "ERROR unable to load key and token values from the registry.")
      $response = $null
    }
    return $response
  }
}
