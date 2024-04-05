Add-Type -Path "C:\Users\sccmclientpush\Desktop\Tools\MemoryInspector.dll"

$processes = Get-Process

foreach ($process in $processes) {
    try {
        [MemoryInspector]::InspectProcess($process)
    } catch {
        Write-Host "Failed to inspect process: $($process.ProcessName)"
    }
}
