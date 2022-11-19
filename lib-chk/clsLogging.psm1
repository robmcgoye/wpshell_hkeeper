class Logging{
    [string]$EventLogFolder
    [string]$EventLogSource

    Logging()
    {
        $this.EventLogFolder = ""
        $this.EventLogSource = ""
    }

    Logging([string]$logfolder, [string]$logsource)
    {
        $this.EventLogFolder = $logfolder
        $this.EventLogSource = $logsource
    }
    
    write_event([int]$entry_type, [int]$event_id, [string]$message) 
    {
        #entryType: 1=error, 2=warning, 3=info
        if(-not([System.Diagnostics.EventLog]::Exists($this.EventLogFolder))) {
            New-Eventlog -ComputerName $env:COMPUTERNAME -LogName $this.EventLogFolder -Source $this.EventLogSource
            Limit-EventLog -ComputerName $env:COMPUTERNAME -LogName $this.EventLogFolder -OverflowAction OverwriteAsNeeded -MaximumSize 128KB
        }
        if(-not([System.Diagnostics.EventLog]::SourceExists($this.EventLogSource))) {
            [System.Diagnostics.EventLog]::CreateEventSource($this.EventLogSource, $this.EventLogFolder)
        }
        if($message.Length -gt 31895) {
            $message = $message.Substring(1,31840)
            $message = "WARNING WARNING This event has been truncated!! `n" + $message
        }
        if ($entry_type -eq 1) {
            Write-EventLog -ComputerName $env:COMPUTERNAME -LogName $this.EventLogFolder -Source $this.EventLogSource -EntryType Error  -Message $message -EventId $event_id
        } elseif($entry_type -eq 2) {
            Write-EventLog -ComputerName $env:COMPUTERNAME -LogName $this.EventLogFolder -Source $this.EventLogSource -EntryType Warning  -Message $message -EventId $event_id
        } elseif($entry_type -eq 3) {
            Write-EventLog -ComputerName $env:COMPUTERNAME -LogName $this.EventLogFolder -Source $this.EventLogSource -EntryType Information  -Message $message -EventId $event_id
        }
    }
}

