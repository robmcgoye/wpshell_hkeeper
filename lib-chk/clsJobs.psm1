Using module ".\clsApiKeys.psm1"
Using module ".\clsApiUrls.psm1"
Using module ".\clsHardware.psm1"
Using module ".\clsLogging.psm1"
Using module ".\clsWebRequest.psm1"

class Jobs 
{
  [string]$token
  [string]$api_base_url

  hidden [bool]initialized()
  {
    $init = $false
    if (($null -ne $this.token) -and ($null -ne $this.api_base_url)) {
      $init = $true
    }
    return $init
  }

  Jobs ([string]$url, [string]$t) 
  {
    $this.api_base_url = $url
    $this.token = $t
  }

  [bool]mark_completed([Logging]$event_logger, [int]$job_id)
  {
    $ok = $false
    if ($this.initialized()) {
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new($api_url.create_completed_job($job_id), ($api_url.get_auth_header($this.token)))
      $response = $api_request.post($null)
      if ($api_request.getstatus() -eq -1) {
        $event_logger.write_event(1, 404, "ERROR ${response}.")
      } elseif ($api_request.getstatus() -eq 422) {
        $event_logger.write_event(2, 202, "Failed marking job as completed. $($response.message)")
      } elseif ($api_request.getstatus() -eq 200) {
        $event_logger.write_event(3, 301, "Marked job as completed with id ${job_id}.")
        $ok = $true
      } else {
        $event_logger.write_event(1, 403, "ERROR server returned $($api_request.getstatus()) response code with the following message: $($response.message).")
      }
  } else {
      $event_logger.write_event(1, 101, "ERROR: jobs class not properly initialized")
    }
    return $ok
  }

  [PSCustomObject]get_jobs([Logging]$event_logger, [int]$computer_id) 
  {
    $response = $null
    if ($this.initialized()) {
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new($api_url.get_computer_jobs($computer_id), ($api_url.get_auth_header($this.token)))
      $response = $api_request.get()
      if ($api_request.getstatus() -ne 200){
        $event_logger.write_event(1, 104, "ERROR: the server returned this code $($api_request.getstatus()). The message was: $($response.message)")
        $response = $null
      } else {
        $event_logger.write_event(3, 200, "LOADED jobs from the server")
      }   
    } else {
      $event_logger.write_event(1, 101, "ERROR: jobs class not properly initialized")
    }
    return $response  
  }

  [bool]create_event([Logging]$event_logger, [int]$job_id, [int]$status, [string]$notes)
  {
    $ok = $false
    if ($this.initialized()) {
      $api_url = [ApiUrls]::new($this.api_base_url)
      $api_request = [RestfulRequest]::new($api_url.create_job_event($job_id), ($api_url.get_auth_header($this.token)))
      $response = $api_request.post($this.build_event_record($status, $notes))
      if ($api_request.getstatus() -eq -1) {
        $event_logger.write_event(1, 404, "ERROR ${response}.")
      } elseif ($api_request.getstatus() -eq 422) {
        $event_logger.write_event(2, 302, "Failed creating job event. $($response.message)")
      } elseif ($api_request.getstatus() -eq 200) {
        $ok = $true
      } else {
        $event_logger.write_event(3, 403, "ERROR server returned $($api_request.getstatus()) response code with the following message: $($response.message).")
      }
   } else {
      $event_logger.write_event(1, 101, "ERROR: jobs class not properly initialized")
    }
    return $ok
  }

  hidden [hashtable]build_event_record([int]$status, [string]$notes)
  {
    $record = @{
      "status" = $status;
      "notes" = $notes;
    }
    return @{ "job_event" = $record }
}
}