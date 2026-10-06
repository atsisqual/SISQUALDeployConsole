Set-StrictMode -Version Latest

if (-not ('Sisqual.Runtime.BootstrapLogNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Sisqual.Runtime
{
    internal sealed class BootstrapLogDirectoryGuard : IDisposable
    {
        private readonly List<SafeFileHandle> _handles;
        internal BootstrapLogDirectoryGuard(List<SafeFileHandle> handles) { _handles = handles; }
        public void Dispose()
        {
            for (int i = _handles.Count - 1; i >= 0; i--) _handles[i].Dispose();
            _handles.Clear();
        }
    }

    public static class BootstrapLogNative
    {
        private const uint GENERIC_READ = 0x80000000;
        private const uint FILE_READ_ATTRIBUTES = 0x00000080;
        private const uint FILE_APPEND_DATA = 0x00000004;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint OPEN_EXISTING = 3;
        private const uint OPEN_ALWAYS = 4;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
        private const int FileAttributeTagInfo = 9;
        private const int ERROR_ALREADY_EXISTS = 183;

        [StructLayout(LayoutKind.Sequential)]
        private struct FILE_ATTRIBUTE_TAG_INFO
        {
            public uint FileAttributes;
            public uint ReparseTag;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint LowDateTime;
            public uint HighDateTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION
        {
            public uint FileAttributes;
            public FILETIME CreationTime;
            public FILETIME LastAccessTime;
            public FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateDirectoryW(string lpPathName, IntPtr lpSecurityAttributes);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle hFile,
            StringBuilder lpszFilePath,
            uint cchFilePath,
            uint dwFlags);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle hFile,
            out BY_HANDLE_FILE_INFORMATION lpFileInformation);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle hFile,
            int FileInformationClass,
            out FILE_ATTRIBUTE_TAG_INFO lpFileInformation,
            uint dwBufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool WriteFile(
            SafeFileHandle hFile,
            byte[] lpBuffer,
            uint nNumberOfBytesToWrite,
            out uint lpNumberOfBytesWritten,
            IntPtr lpOverlapped);

        private static string NormalizePath(string path)
        {
            string value = path;
            if (value.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
                value = @"\\" + value.Substring(8);
            else if (value.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
                value = value.Substring(4);
            return Path.GetFullPath(value).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }

        private static string GetFinalPath(SafeFileHandle handle)
        {
            var buffer = new StringBuilder(512);
            uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            if (length >= buffer.Capacity)
            {
                buffer = new StringBuilder((int)length + 1);
                length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return NormalizePath(buffer.ToString());
        }

        private static void ValidateHandle(SafeFileHandle handle, string expectedPath, string label)
        {
            FILE_ATTRIBUTE_TAG_INFO info;
            if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, out info, (uint)Marshal.SizeOf<FILE_ATTRIBUTE_TAG_INFO>()))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if ((info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                throw new IOException(label + " is a reparse point and is not approved: " + expectedPath);

            string expected = NormalizePath(expectedPath);
            string actual = GetFinalPath(handle);
            if (!string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
                throw new IOException(label + " resolved outside its validated path. Expected " + expected + ", got " + actual + ".");
        }

        private static void ValidateSingleLinkFile(SafeFileHandle handle, string expectedPath)
        {
            ValidateHandle(handle, expectedPath, "Bootstrap log file");
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (info.NumberOfLinks != 1)
                throw new IOException("Bootstrap log file must have exactly one hard link; found " + info.NumberOfLinks + ": " + expectedPath);
        }

        private static SafeFileHandle OpenDirectory(string path)
        {
            var handle = CreateFileW(
                path,
                GENERIC_READ | FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot guard bootstrap log directory: " + path);
            try
            {
                ValidateHandle(handle, path, "Bootstrap log directory");
                return handle;
            }
            catch
            {
                handle.Dispose();
                throw;
            }
        }

        private static Stack<string> BuildDirectoryStack(string path)
        {
            string full = Path.GetFullPath(path);
            var stack = new Stack<string>();
            var current = new DirectoryInfo(full);
            while (current != null)
            {
                stack.Push(current.FullName);
                current = current.Parent;
            }
            return stack;
        }

        private static BootstrapLogDirectoryGuard GuardDirectoryTree(string path)
        {
            var stack = BuildDirectoryStack(path);
            var handles = new List<SafeFileHandle>();
            try
            {
                while (stack.Count > 0)
                {
                    string directory = stack.Pop();
                    if (!Directory.Exists(directory)) throw new DirectoryNotFoundException(directory);
                    handles.Add(OpenDirectory(directory));
                }
                return new BootstrapLogDirectoryGuard(handles);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static IDisposable EnsureDirectoryTree(string path)
        {
            var stack = BuildDirectoryStack(path);
            var handles = new List<SafeFileHandle>();
            try
            {
                while (stack.Count > 0)
                {
                    string directory = stack.Pop();
                    if (!Directory.Exists(directory))
                    {
                        if (!CreateDirectoryW(directory, IntPtr.Zero))
                        {
                            int error = Marshal.GetLastWin32Error();
                            if (error != ERROR_ALREADY_EXISTS)
                                throw new Win32Exception(error, "Cannot create guarded bootstrap log directory: " + directory);
                        }
                    }
                    handles.Add(OpenDirectory(directory));
                }
                return new BootstrapLogDirectoryGuard(handles);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static void AppendAscii(string path, string text)
        {
            string fullPath = Path.GetFullPath(path);
            string directory = Path.GetDirectoryName(fullPath);
            if (string.IsNullOrEmpty(directory)) throw new IOException("Bootstrap log path has no parent directory: " + fullPath);

            using (var directoryGuard = GuardDirectoryTree(directory))
            {
                var handle = CreateFileW(
                    fullPath,
                    FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
                    0,
                    IntPtr.Zero,
                    OPEN_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
                    IntPtr.Zero);
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open bootstrap log file: " + fullPath);
                using (handle)
                {
                    ValidateSingleLinkFile(handle, fullPath);
                    byte[] bytes = Encoding.ASCII.GetBytes(text + Environment.NewLine);
                    uint written;
                    if (!WriteFile(handle, bytes, (uint)bytes.Length, out written, IntPtr.Zero))
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot append bootstrap log file: " + fullPath);
                    if (written != bytes.Length) throw new IOException("Incomplete bootstrap log write: " + fullPath);
                    ValidateSingleLinkFile(handle, fullPath);
                }
            }
        }
    }
}
'@
}

function Get-SisqualRuntimeDefaults {
    [CmdletBinding()]
    param()

    [pscustomobject][ordered]@{
        ExpectedPowerShellVersion = '7.6.6'
        ApprovedLogRoot = 'C:\SISQUALWFM\WFM.Logs'
        DefaultLogRoot = 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement'
        RetentionDays = 30
        LogPrefix = 'SISQUALDeployConsole'
        ManifestFileName = 'package-manifest.json'
    }
}

function Test-SisqualRuntimeHost {
    [CmdletBinding()]
    param([string]$ExpectedVersion = '7.6.6')

    $actualVersion = $PSVersionTable.PSVersion.ToString()
    $edition = [string]$PSVersionTable.PSEdition
    $is64Bit = [Environment]::Is64BitProcess
    $success = ($actualVersion -ceq $ExpectedVersion -and $edition -ceq 'Core' -and $is64Bit)

    [pscustomobject][ordered]@{
        Success = $success
        ExpectedVersion = $ExpectedVersion
        ActualVersion = $actualVersion
        PSEdition = $edition
        Is64BitProcess = $is64Bit
        PSHome = $PSHOME
    }
}

function Assert-SisqualBootstrapPathNoReparse {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label contains an existing reparse point: $current"
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -ceq $current) { break }
        $current = $parent.FullName
    }
}

function Resolve-SisqualBootstrapLogRoot {
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][string]$ApprovedRoot
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot) -or [string]::IsNullOrWhiteSpace($ApprovedRoot)) {
        throw 'LogRoot and ApprovedRoot are required.'
    }
    if (-not [IO.Path]::IsPathRooted($LogRoot) -or -not [IO.Path]::IsPathRooted($ApprovedRoot)) {
        throw 'Runtime log paths must be absolute.'
    }
    if ($LogRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $ApprovedRoot.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for bootstrap logs.'
    }

    $fullRoot = [IO.Path]::GetFullPath($LogRoot)
    $fullApproved = [IO.Path]::GetFullPath($ApprovedRoot)
    if ($fullRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $fullApproved.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for bootstrap logs.'
    }

    $driveRoot = [IO.Path]::GetPathRoot($fullApproved)
    $drive = [IO.DriveInfo]::new($driveRoot)
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Bootstrap logs require an absolute path on a fixed local drive.'
    }

    $separator = [IO.Path]::DirectorySeparatorChar
    $approvedPrefix = $fullApproved.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $fullRoot.Equals($fullApproved, [StringComparison]::Ordinal) -and
        -not $fullRoot.StartsWith($approvedPrefix, [StringComparison]::Ordinal)) {
        throw "LogRoot is outside the approved local log root: $fullApproved"
    }

    Assert-SisqualBootstrapPathNoReparse -Path $fullApproved -Label 'ApprovedRoot'
    Assert-SisqualBootstrapPathNoReparse -Path $fullRoot -Label 'LogRoot'

    [pscustomobject]@{ LogRoot = $fullRoot; ApprovedRoot = $fullApproved }
}

function Get-SisqualDailyLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )
    Join-Path $LogRoot ('{0}-{1}.log' -f $Prefix, $NowUtc.ToString('yyyy-MM-dd'))
}

function Remove-SisqualExpiredLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )

    # Destructive retention is deliberately deferred until the hardened runtime logger is wired
    # after the package-integrity gate. The pre-integrity bootstrap must not enumerate/delete log
    # files through pathname-based APIs merely to enforce retention.
    return @()
}

function Initialize-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [string]$ApprovedRoot = 'C:\SISQUALWFM\WFM.Logs',
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    # Resolve the policy boundary first, then create/validate every missing directory component
    # while already-open ancestors remain guarded without write/delete sharing. No destructive
    # retention is performed before package integrity has been established.
    $resolved = Resolve-SisqualBootstrapLogRoot -LogRoot $LogRoot -ApprovedRoot $ApprovedRoot
    $creationGuard = $null
    try {
        $creationGuard = [Sisqual.Runtime.BootstrapLogNative]::EnsureDirectoryTree($resolved.LogRoot)
    }
    finally {
        if ($null -ne $creationGuard) {
            $creationGuard.Dispose()
        }
    }

    $logPath = Get-SisqualDailyLogPath -LogRoot $resolved.LogRoot -NowUtc $NowUtc

    [pscustomobject][ordered]@{
        ApprovedRoot = $resolved.ApprovedRoot
        LogRoot = $resolved.LogRoot
        LogPath = $logPath
        RetentionDays = $RetentionDays
        RemovedExpiredLogs = @()
        RetentionDeferred = $true
    }
}

function Write-SisqualBootstrapEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][ValidateSet('BOOTSTRAP_STARTED','HOST_VALID','MANIFEST_MISSING','INTEGRITY_VERIFIER_UNAVAILABLE','BOOTSTRAP_FATAL')][string]$EventId,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    $messages = @{
        BOOTSTRAP_STARTED = 'Runtime bootstrap started.'
        HOST_VALID = 'Pinned portable PowerShell host validated.'
        MANIFEST_MISSING = 'Package manifest is missing; startup is blocked.'
        INTEGRITY_VERIFIER_UNAVAILABLE = 'Package integrity verifier is not integrated yet; startup is blocked.'
        BOOTSTRAP_FATAL = 'Runtime bootstrap failed before application startup.'
    }
    $line = '{0} [{1}] {2} pid={3} {4}' -f $NowUtc.ToString('o'), $Level, $EventId, $PID, $messages[$EventId]
    [Sisqual.Runtime.BootstrapLogNative]::AppendAscii([IO.Path]::GetFullPath($LogPath), $line)
}
