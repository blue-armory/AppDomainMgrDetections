using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class MemoryInspector {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORY_BASIC_INFORMATION {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    const int PROCESS_QUERY_INFORMATION = 0x0400;
    const int PROCESS_VM_READ = 0x0010;

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(int processAccess, bool bInheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("kernel32.dll")]
    public static extern int VirtualQueryEx(IntPtr hProcess, IntPtr lpAddress, out MEMORY_BASIC_INFORMATION lpBuffer, uint dwLength);

    [DllImport("psapi.dll", CharSet = CharSet.Auto)]
    public static extern int GetMappedFileName(IntPtr hProcess, IntPtr lpv, StringBuilder lpFilename, int nSize);

    public static void InspectProcess(Process process) {
        IntPtr processHandle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, process.Id);

        if (processHandle == IntPtr.Zero) {
            Console.WriteLine(String.Format("Failed to open process: {0} (ID: {1})", process.ProcessName, process.Id));
            return;
        }

        try {
            IntPtr address = IntPtr.Zero;
            MEMORY_BASIC_INFORMATION mbi = new MEMORY_BASIC_INFORMATION();

            while (true) {
                if (VirtualQueryEx(processHandle, address, out mbi, (uint)Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION))) == 0) {
                    break;
                }

                if (mbi.Protect == 0x40) { // PAGE_EXECUTE_WRITECOPY
                    StringBuilder filename = new StringBuilder(1024);
                    if (GetMappedFileName(processHandle, mbi.BaseAddress, filename, filename.Capacity) != 0) {
                        Console.WriteLine(String.Format("Process: {0} (ID: {1}), Address: {2}, Size: {3}, File: {4}", process.ProcessName, process.Id, mbi.BaseAddress, mbi.RegionSize, filename.ToString()));
                    } else {
                        Console.WriteLine(String.Format("Process: {0} (ID: {1}), Address: {2}, Size: {3}, File: [Could not determine]", process.ProcessName, process.Id, mbi.BaseAddress, mbi.RegionSize));
                    }
                }

                unchecked {
                    address = new IntPtr(address.ToInt64() + (long)mbi.RegionSize);
                }

                if (address == IntPtr.Zero) {
                    break;
                }
            }
        } catch (Exception ex) {
            Console.WriteLine(String.Format("Failed to inspect process: {0} (ID: {1}), Error: {2}", process.ProcessName, process.Id, ex.Message));
        } finally {
            CloseHandle(processHandle);
        }
    }
}
