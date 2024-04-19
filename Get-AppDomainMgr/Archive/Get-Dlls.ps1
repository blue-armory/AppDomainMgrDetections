# Get all running processes
$processes = Get-Process

foreach ($process in $processes) {
    try {
        # Output the process name and main module file path
        Write-Host "Process: $($process.ProcessName) (ID: $($process.Id))"
        Write-Host "`tProcess Path: $($process.MainModule.FileName)"

        # Get the loaded modules for the process
        $modules = $process.Modules

        # Filter and display .NET assemblies
        $modules | Where-Object { $_.FileName -like "*.dll" -or $_.FileName -like "*.exe" } | ForEach-Object {
            Write-Host "`tAssembly: $($_.FileName)"
        }
    } catch {
        # Error handling in case the process modules cannot be accessed
        Write-Host "`tCannot access modules for process $($process.ProcessName) due to permissions or because the process has exited."
    }
}
