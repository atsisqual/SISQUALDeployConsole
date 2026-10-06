#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DefaultApprovedLogRoot = 'C:\SISQUALWFM\WFM.Logs'
$script:DefaultLogRoot = 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement'
$script:DefaultRetentionDays = 30
$script:DefaultPrefix = 'SISQUALDeployConsole'
$script:LogState = $null
$script:WriteLock = [object]::new()

if (-not ('Sisqual.Runtime.LogNative' -as [type])) {
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
    public sealed class LogDirectoryGuard : IDisposable
    {
        private readonly List<SafeFileHandle> _handles;
        internal LogDirectoryGuard(List<SafeFileHandle> handles) { _handles = handles; }
        public void Dispose()
        {
            for (int i = _handles.Count - 1; i >= 0; i--) _handles[i].Dispose();
            _handles.Clear();
        }
    }

    public static class LogNative
    {
        private const uint FILE_READ_ATTRIBUTES = 0x00000080;
        private const uint FILE_APPEND_DATA = 0x00000004;
        private const uint DELETE = 0x00010000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint OPEN_ALWAYS = 4;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
        private const int ERROR_ALREADY_EXISTS = 183;
        private const int FileDispositionInfo = 4;
        private const int FileAttributeTagInfo = 9;

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

        [StructLayout(LayoutKind.Sequential)]
        private struct FILE_DISPOSITION_INFO
        {
            [MarshalAs(UnmanagedType.Bool)]
            public bool DeleteFile;
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
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle hFile,
            int FileInformationClass,
            out FILE_ATTRIBUTE_TAG_INFO lpFileInformation,
            uint dwBufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle hFile,
            int FileInformationClass,
            ref FILE_DISPOSITION_INFO lpFileInformation,
            uint dwBufferSize);

        [DllImport("kernel32.dll", SetLastError = true)]
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

        private static void ValidateSingleLinkFile(SafeFileHandle handle, string expectedPath, string label)
        {
            ValidateHandle(handle, expectedPath, label);
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (info.NumberOfLinks != 1)
                throw new IOException(label + " must have exactly one hard link; found " + info.NumberOfLinks + ": " + expectedPath);
        }

        private static SafeFileHandle OpenDirectory(string path)
        {
            var handle = CreateFileW(
                path,
                FILE_READ_ATTRIBUTES,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot guard directory: " + path);
            try
            {
                ValidateHandle(handle, path, "Log directory");
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

        public static LogDirectoryGuard GuardDirectoryTree(string path)
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
                return new LogDirectoryGuard(handles);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static LogDirectoryGuard EnsureDirectoryTree(string path)
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
                                throw new Win32Exception(error, "Cannot create guarded log directory: " + directory);
                        }
                    }
                    handles.Add(OpenDirectory(directory));
                }
                return new LogDirectoryGuard(handles);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }

        public static void AppendUtf8(string path, string text)
        {
            var handle = CreateFileW(
                path,
                FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
                0,
                IntPtr.Zero,
                OPEN_ALWAYS,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open log file: " + path);
            using (handle)
            {
                ValidateSingleLinkFile(handle, path, "Log file");
                byte[] bytes = new UTF8Encoding(false).GetBytes(text);
                uint written;
                if (!WriteFile(handle, bytes, (uint)bytes.Length, out written, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot append log file: " + path);
                if (written != bytes.Length) throw new IOException("Incomplete log write: " + path);
                ValidateSingleLinkFile(handle, path, "Log file");
            }
        }

        public static void DeleteByHandle(string path)
        {
            var handle = CreateFileW(
                path,
                DELETE | FILE_READ_ATTRIBUTES,
                0,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open log file for deletion: " + path);
            using (handle)
            {
                ValidateSingleLinkFile(handle, path, "Retention file");
                var disposition = new FILE_DISPOSITION_INFO { DeleteFile = true };
                if (!SetFileInformationByHandle(handle, FileDispositionInfo, ref disposition, (uint)Marshal.SizeOf<FILE_DISPOSITION_INFO>()))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot delete retained log file: " + path);
            }
        }
    }
}
'@
}

function Protect-SisqualRuntimeLogText {
    param(
        [AllowNull()]
        [object]$Value
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }

    $headerPattern = '(?i)\b(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]*(?:(?:\r\n|\r|\n)[ \t]+[^\r\n]*)*'
    $text = [regex]::Replace($text, $headerPattern, '$1: [REDACTED]')
    $text = [regex]::Replace($text, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', '$1 [REDACTED]')

    $sensitiveNamePattern = 'password|passwd|pwd|secret|token|client[_-]?secret|authorization|cookie|api[_-]?key|connection[_-]?string'

    # A log field can contain arbitrary text plus a serialized JSON fragment. Once a quoted
    # sensitive JSON key is detected, redact the remainder of the field rather than trying to
    # parse attacker-controlled scalar/composite/multiline JSON with regular expressions.
    $serializedSensitivePattern = '(?is)"(' + $sensitiveNamePattern + ')"\s*:'
    $serializedMatch = [regex]::Match($text, $serializedSensitivePattern)
    if ($serializedMatch.Success) {
        $text = $text.Substring(0, $serializedMatch.Index) + $serializedMatch.Groups[1].Value + '=[REDACTED]'
    }

    $doubleQuotedValue = '"(?:\\.|[^"\\])*"'
    $singleQuotedValue = '''(?:\\.|[^''\\])*'''
    $assignmentPattern = '(?i)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]\s*(' + $doubleQuotedValue + '|' + $singleQuotedValue + '|[^\s,;}\]]+)'
    $text = [regex]::Replace($text, $assignmentPattern, '$1=[REDACTED]')

    $text = $text -replace "`r`n|`r|`n", '\n'
    return $text
}

function Test-SisqualSensitiveLogField {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $Name -match '(?i)(secret|password|passwd|pwd|token|authorization|cookie|credential|private.?key|client.?secret|api.?key|connection.?string)'
}

function Assert-SisqualNoReparsePoint {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label contains a reparse point and is not approved: $($item.FullName)"
            }
        }

        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -ceq $current) {
            break
        }
        $current = $parent.FullName
    }
}

function Assert-SisqualRuntimeLogRootStillApproved {
    if ($null -eq $script:LogState) {
        throw 'Runtime logging has not been initialized.'
    }

    Assert-SisqualNoReparsePoint -Path $script:LogState.ApprovedRoot -Label 'ApprovedRoot'
    Assert-SisqualNoReparsePoint -Path $script:LogState.LogRoot -Label 'LogRoot'
}

function Resolve-SisqualRuntimeLogRoot {
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot,
        [Parameter(Mandatory)]
        [string]$ApprovedRoot
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        throw 'LogRoot cannot be empty.'
    }
    if ([string]::IsNullOrWhiteSpace($ApprovedRoot)) {
        throw 'ApprovedRoot cannot be empty.'
    }
    if (-not [System.IO.Path]::IsPathRooted($LogRoot) -or -not [System.IO.Path]::IsPathRooted($ApprovedRoot)) {
        throw 'LogRoot and ApprovedRoot must be absolute local paths.'
    }

    $fullRoot = [System.IO.Path]::GetFullPath($LogRoot)
    $fullApprovedRoot = [System.IO.Path]::GetFullPath($ApprovedRoot)
    if ($fullRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $fullApprovedRoot.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for runtime logs.'
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $approvedPrefix = $fullApprovedRoot.TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    $isApprovedRoot = $fullRoot.Equals($fullApprovedRoot, [StringComparison]::OrdinalIgnoreCase)
    $isApprovedChild = $fullRoot.StartsWith($approvedPrefix, [StringComparison]::OrdinalIgnoreCase)
    if (-not $isApprovedRoot -and -not $isApprovedChild) {
        throw "LogRoot is outside the approved local log root: $fullApprovedRoot"
    }

    Assert-SisqualNoReparsePoint -Path $fullApprovedRoot -Label 'ApprovedRoot'
    Assert-SisqualNoReparsePoint -Path $fullRoot -Label 'LogRoot'

    return [pscustomobject]@{
        LogRoot = $fullRoot
        ApprovedRoot = $fullApprovedRoot
    }
}

function Invoke-SisqualRuntimeLogRetentionCore {
    param(
        [Parameter(Mandatory)]
        [datetime]$ReferenceUtc
    )

    Assert-SisqualRuntimeLogRootStillApproved

    $reference = $ReferenceUtc.ToUniversalTime()
    $todayUtc = [DateOnly]::FromDateTime($reference)
    $cutoffDate = $todayUtc.AddDays(-($script:LogState.RetentionDays - 1))
    $pattern = '^' + [regex]::Escape($script:LogState.Prefix) + '-(\d{4}-\d{2}-\d{2})\.log$'
    $removed = 0
    $guard = [Sisqual.Runtime.LogNative]::GuardDirectoryTree($script:LogState.LogRoot)
    try {
        foreach ($file in @(Get-ChildItem -LiteralPath $script:LogState.LogRoot -File -Filter ($script:LogState.Prefix + '-*.log') -ErrorAction Stop)) {
            if ($file.Name -notmatch $pattern) {
                continue
            }

            $fileDate = [DateOnly]::MinValue
            $parsed = [DateOnly]::TryParseExact(
                $Matches[1],
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$fileDate
            )
            if (-not $parsed) {
                continue
            }

            if ($fileDate -lt $cutoffDate) {
                [Sisqual.Runtime.LogNative]::DeleteByHandle($file.FullName)
                $removed++
            }
        }
    }
    finally {
        $guard.Dispose()
    }

    $script:LogState.LastRetentionUtcDate = $todayUtc
    return $removed
}

function Get-SisqualRuntimeLogDefaults {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ApprovedRoot = $script:DefaultApprovedLogRoot
        LogRoot = $script:DefaultLogRoot
        RetentionDays = $script:DefaultRetentionDays
        Prefix = $script:DefaultPrefix
    }
}

function Initialize-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [string]$LogRoot = $script:DefaultLogRoot,
        [string]$ApprovedRoot = $script:DefaultApprovedLogRoot,
        [ValidateRange(1, 3650)]
        [int]$RetentionDays = $script:DefaultRetentionDays,
        [ValidatePattern('^[A-Za-z0-9_.-]{1,64}$')]
        [string]$Prefix = $script:DefaultPrefix
    )

    $resolved = Resolve-SisqualRuntimeLogRoot -LogRoot $LogRoot -ApprovedRoot $ApprovedRoot
    $approvedGuard = [Sisqual.Runtime.LogNative]::EnsureDirectoryTree($resolved.ApprovedRoot)
    try {
        $logGuard = [Sisqual.Runtime.LogNative]::EnsureDirectoryTree($resolved.LogRoot)
        try {
            Assert-SisqualNoReparsePoint -Path $resolved.ApprovedRoot -Label 'ApprovedRoot'
            Assert-SisqualNoReparsePoint -Path $resolved.LogRoot -Label 'LogRoot'
        }
        finally {
            $logGuard.Dispose()
        }
    }
    finally {
        $approvedGuard.Dispose()
    }

    $script:LogState = [pscustomobject]@{
        ApprovedRoot = $resolved.ApprovedRoot
        LogRoot = $resolved.LogRoot
        RetentionDays = $RetentionDays
        Prefix = $Prefix
        LastRetentionUtcDate = $null
    }

    Invoke-SisqualRuntimeLogRetention | Out-Null
    return [pscustomobject]@{
        ApprovedRoot = $script:LogState.ApprovedRoot
        LogRoot = $script:LogState.LogRoot
        RetentionDays = $script:LogState.RetentionDays
        Prefix = $script:LogState.Prefix
    }
}

function Invoke-SisqualRuntimeLogRetention {
    [CmdletBinding()]
    param(
        [datetime]$ReferenceUtc = [datetime]::UtcNow
    )

    if ($null -eq $script:LogState) {
        throw 'Runtime logging has not been initialized.'
    }

    [System.Threading.Monitor]::Enter($script:WriteLock)
    try {
        return Invoke-SisqualRuntimeLogRetentionCore -ReferenceUtc $ReferenceUtc
    }
    finally {
        [System.Threading.Monitor]::Exit($script:WriteLock)
    }
}

function Write-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9_.-]{1,64}$')]
        [string]$EventCode,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [System.Collections.IDictionary]$Properties,

        [datetime]$TimestampUtc = [datetime]::UtcNow
    )

    if ($null -eq $script:LogState) {
        throw 'Runtime logging has not been initialized.'
    }

    $timestamp = $TimestampUtc.ToUniversalTime()
    $retentionNowUtc = [datetime]::UtcNow
    $retentionUtcDate = [DateOnly]::FromDateTime($retentionNowUtc)
    $fileName = '{0}-{1}.log' -f $script:LogState.Prefix, $timestamp.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $path = Join-Path $script:LogState.LogRoot $fileName
    $safeMessage = Protect-SisqualRuntimeLogText -Value $Message
    $parts = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $Properties) {
        foreach ($keyObject in @($Properties.Keys | Sort-Object { [string]$_ })) {
            $key = [string]$keyObject
            if ($key -notmatch '^[A-Za-z0-9_.-]{1,64}$') {
                throw "Unsafe log property name: $key"
            }

            $value = if (Test-SisqualSensitiveLogField -Name $key) {
                '[REDACTED]'
            }
            else {
                Protect-SisqualRuntimeLogText -Value $Properties[$keyObject]
            }
            $value = $value.Replace('"', '\"')
            $parts.Add(('{0}="{1}"' -f $key, $value))
        }
    }

    $line = '{0} [{1}] {2} {3}' -f $timestamp.ToString('o', [Globalization.CultureInfo]::InvariantCulture), $Level, $EventCode, $safeMessage
    if ($parts.Count -gt 0) {
        $line += ' ' + ($parts -join ' ')
    }

    [System.Threading.Monitor]::Enter($script:WriteLock)
    try {
        Assert-SisqualRuntimeLogRootStillApproved
        if ($null -eq $script:LogState.LastRetentionUtcDate -or $retentionUtcDate -gt $script:LogState.LastRetentionUtcDate) {
            Invoke-SisqualRuntimeLogRetentionCore -ReferenceUtc $retentionNowUtc | Out-Null
        }

        $guard = [Sisqual.Runtime.LogNative]::GuardDirectoryTree($script:LogState.LogRoot)
        try {
            [Sisqual.Runtime.LogNative]::AppendUtf8($path, $line + [Environment]::NewLine)
        }
        finally {
            $guard.Dispose()
        }
    }
    finally {
        [System.Threading.Monitor]::Exit($script:WriteLock)
    }

    return $path
}

Export-ModuleMember -Function Get-SisqualRuntimeLogDefaults, Initialize-SisqualRuntimeLog, Invoke-SisqualRuntimeLogRetention, Write-SisqualRuntimeLog