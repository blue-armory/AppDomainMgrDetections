$code = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Diagnostics;

public static class NativeMethods
{
    public const uint PAGE_EXECUTE_WRITECOPY = 0x80;
    public const int PROCESS_QUERY_INFORMATION = 0x0400;
    public const int PROCESS_VM_READ = 0x0010;

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION lpBuffer, uint dwLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool EnumProcessModules(IntPtr hProcess, [Out] IntPtr lphModule, uint cb, out uint lpcbNeeded);

    [DllImport("psapi.dll", SetLastError = true)]
    public static extern uint GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, StringBuilder lpBaseName, uint nSize);
}
"@ 

Add-Type -TypeDefinition $code -Language CSharp


function Get-ProtectedMemoryRegions {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process]$Process
    )
    try {
        $processHandle = [NativeMethods]::OpenProcess([NativeMethods]::PROCESS_QUERY_INFORMATION -bor [NativeMethods]::PROCESS_VM_READ, $false, $Process.Id)

        if ($processHandle -eq [IntPtr]::Zero) {
            throw "Unable to open process for PID: $($Process.Id)"
        }

        $minAddress = [IntPtr]::Zero
$maxAddress = [IntPtr]::Add([IntPtr]::Zero, 0x7FFFFFFF00000000) # Adjusted for 64-bit address space limit
$memoryInfo = New-Object NativeMethods+MEMORY_BASIC_INFORMATION
$memoryInfoSize = [System.Runtime.InteropServices.Marshal]::SizeOf($memoryInfo.GetType())

while ($minAddress.ToInt64() -lt $maxAddress.ToInt64()) {
    if (-not [NativeMethods]::VirtualQueryEx($processHandle, $minAddress, [ref] $memoryInfo, [uint32]$memoryInfoSize)) {
        # Move to the next region
        $minAddress = [IntPtr]::Add($minAddress, [IntPtr]::Size)
    } else {
        if ($memoryInfo.Protect -eq [NativeMethods]::PAGE_EXECUTE_WRITECOPY -and $memoryInfo.State -eq 0x1000) {
            $moduleName = Get-ModuleForMemoryRegion -ProcessHandle $processHandle -MemoryAddress $memoryInfo.BaseAddress
            if ($moduleName) {
                [PSCustomObject]@{
                    PID = $Process.Id
                    BaseAddress = $memoryInfo.BaseAddress
                    RegionSize = $memoryInfo.RegionSize
                    ModuleName = $moduleName
                } | Format-Table -AutoSize
            }
        }

        $minAddress = [IntPtr]::Add($memoryInfo.BaseAddress, $memoryInfo.RegionSize.ToInt64())
    }
}
    }
    catch {
        Write-Error $_.Exception.Message
    }
    finally {
        if ($processHandle -ne [IntPtr]::Zero) {
            [NativeMethods]::CloseHandle($processHandle)
        }
    }
}

function Get-ModuleForMemoryRegion {
    param(
        [Parameter(Mandatory=$true)]
        [IntPtr]$ProcessHandle,
        
        [Parameter(Mandatory=$true)]
        [IntPtr]$MemoryAddress
    )

    $modules = New-Object System.Collections.Generic.List[IntPtr]
    $hModules = [IntPtr]::Zero
    $bytesNeeded = 0

    if ([NativeMethods]::EnumProcessModules($ProcessHandle, $hModules, 0, [ref] $bytesNeeded)) {
        if ($bytesNeeded -gt 0) {
            $hModules = New-Object IntPtr[] -ArgumentList ($bytesNeeded / [IntPtr]::Size)
            if ([NativeMethods]::EnumProcessModules($ProcessHandle, [System.Runtime.InteropServices.Marshal]::UnsafeAddrOfPinnedArrayElement($hModules, 0), $bytesNeeded, [ref] $bytesNeeded)) {
                foreach ($hModule in $hModules) {
                    $modName = New-Object System.Text.StringBuilder 260
                    if ([NativeMethods]::GetModuleFileNameEx($ProcessHandle, $hModule, $modName, $modName.Capacity) -gt 0) {
                        $modules.Add($modName.ToString())
                    }
                }
            }
        }
    }

    foreach ($mod in $modules) {
        # We simply return the module name that corresponds to the memory address queried.
        # A more robust implementation would involve checking if the memory address falls within the module's range.
        return $mod
    }
    return $null
}

# Now use the function to read the memory of each accessible process
Get-Process | ForEach-Object {
    try {
        Get-ProtectedMemoryRegions -Process $_ | Format-Table -AutoSize
    } catch {
        Write-Error "Error processing PID $($_.Id): $($_.Exception.Message)"
    }
}

