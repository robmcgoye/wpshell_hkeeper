class ApiUrls 
{
  [string]$base

  ApiUrls ([string]$url)
  {
    $this.base = $url
  }

  [hashtable]get_auth_header([string]$token)
  {
    return @{ "Authorization" = "Bearer $token" }
  }

  [string]new_computer() 
  {
    return "$($this.base)computers"
  }

  [string]show_computer_by_key([string]$key)
  {
    return "$($this.base)computers/key/${key}"
  }

  [string]update_computer([int]$computer_id)
  {
    return "$($this.base)computers/${computer_id}"
  }

  [string]get_computer_jobs([int]$computer_id)
  {
    return "$($this.base)computers/${computer_id}/jobs"
  }

  [string]create_completed_job([int]$job_id)
  {
    return "$($this.base)jobs/${job_id}/completed"
  }

  [string]create_job_event([int]$job_id)
  {
    return "$($this.base)jobs/${job_id}/job_events"
  }
}