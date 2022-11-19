class RestfulRequest 
{
  [string]$url_command
  [Hashtable]$headers
  [int]$status_code
  
  RestfulRequest([string]$api_url, [Hashtable]$header)
  {
    $this.url_command = $api_url
    $this.headers = $header
    $this.status_code = 0
  }

  [int]getstatus() 
  {
    return $this.status_code
  }

  [PSCustomObject]post([Hashtable]$body) 
  {
    return $this.submit_data("Post", $body)    
  }

  [PSCustomObject]patch([Hashtable]$body) 
  {
    return $this.submit_data("Patch", $body)
  }

  [PSCustomObject]get() 
  {
    return $this.submit_data("Get", $null)
  }

  hidden [PSCustomObject]submit_data([string]$method, [Hashtable]$body) 
  {
    try 
    {
      if ($null -eq $body) {
        $web_response = Invoke-WebRequest -Method $method -Uri $this.url_command -Headers $this.headers -UseBasicParsing
      } else {
        $web_response = Invoke-WebRequest -Method $method -Uri $this.url_command -Body ($body | ConvertTo-Json) -Headers $this.headers -ContentType "application/json" -UseBasicParsing
      }
      $this.status_code = $web_response.StatusCode
      $response = $web_response.Content | ConvertFrom-Json
    }
    catch 
    {
      if ($null -ne $_.Exception.Response) {
        $response = ($this.proccess_error(($_.Exception.Response.GetResponseStream()))) | ConvertFrom-Json
        $this.status_code = $_.Exception.Response.StatusCode
      } else {
        $this.status_code = -1
        $response = $_.ToString()
      }
    }
    return $response    
  }

  hidden [string]proccess_error($response_stream) 
  {
    $reader = New-Object System.IO.StreamReader($response_stream)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    return $reader.ReadToEnd()
  }
}
