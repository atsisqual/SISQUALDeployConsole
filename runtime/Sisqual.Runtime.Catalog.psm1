#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExpectedProviderVersion = '10.0.12'
$script:ExpectedNativeSqliteVersion = '3.53.3'
$script:ProviderState = $null

if (-not ('Sisqual.Runtime.CatalogPathNative' -as [type])) {
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
    public sealed class CatalogPathGuard : IDisposable
    {
        private readonly List<SafeFileHandle> _handles;
        internal CatalogPathGuard(List<SafeFileHandle> handles) { _handles = handles; }
        public void Dispose()
        {
            for (int i = _handles.Count - 1; i >= 0; i--) _handles[i].Dispose();
            _handles.Clear();
        }
    }

    public static class CatalogPathNative
    {
        private const uint FILE_READ_ATTRIBUTES = 0x00000080;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400;
        private const int FileAttributeTagInfo = 9;

        [StructLayout(LayoutKind.Sequential)]
        private struct FILE_ATTRIBUTE_TAG_INFO
        {
            public uint FileAttributes;
            public uint ReparseTag;
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
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle hFile,
            StringBuilder lpszFilePath,
            uint cchFilePath,
            uint dwFlags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle hFile,
            int FileInformationClass,
            out FILE_ATTRIBUTE_TAG_INFO lpFileInformation,
            uint dwBufferSize);

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

        private static SafeFileHandle OpenAndValidate(string path, bool directory, string label)
        {
            uint flags = FILE_FLAG_OPEN_REPARSE_POINT | (directory ? FILE_FLAG_BACKUP_SEMANTICS : FILE_ATTRIBUTE_NORMAL);
            uint shareMode = directory ? FILE_SHARE_READ | FILE_SHARE_WRITE : FILE_SHARE_READ;
            var handle = CreateFileW(
                path,
                FILE_READ_ATTRIBUTES,
                shareMode,
                IntPtr.Zero,
                OPEN_EXISTING,
                flags,
                IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot guard " + label + ": " + path);

            try
            {
                FILE_ATTRIBUTE_TAG_INFO info;
                if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, out info, (uint)Marshal.SizeOf<FILE_ATTRIBUTE_TAG_INFO>()))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                if ((info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0)
                    throw new IOException(label + " is a reparse point and is not approved: " + path);

                string expected = NormalizePath(path);
                string actual = GetFinalPath(handle);
                if (!string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
                    throw new IOException(label + " resolved outside its validated path. Expected " + expected + ", got " + actual + ".");
                return handle;
            }
            catch
            {
                handle.Dispose();
                throw;
            }
        }

        private static bool IsWithin(string root, string target)
        {
            if (string.Equals(root, target, StringComparison.Ordinal)) return true;
            string prefix = root + Path.DirectorySeparatorChar;
            return target.StartsWith(prefix, StringComparison.Ordinal);
        }

        public static CatalogPathGuard GuardPackageMember(string packageRoot, string targetPath, bool targetIsDirectory)
        {
            string root = NormalizePath(packageRoot);
            string target = NormalizePath(targetPath);
            if (!IsWithin(root, target))
                throw new IOException("Guard target is outside PackageRoot: " + target);

            string directoryTarget = targetIsDirectory ? target : Path.GetDirectoryName(target);
            var directories = new Stack<string>();
            var current = new DirectoryInfo(directoryTarget);
            while (current != null)
            {
                string currentPath = NormalizePath(current.FullName);
                if (!IsWithin(root, currentPath)) break;
                directories.Push(currentPath);
                if (string.Equals(currentPath, root, StringComparison.Ordinal)) break;
                current = current.Parent;
            }
            if (directories.Count == 0 || !string.Equals(directories.Peek(), root, StringComparison.Ordinal))
                throw new IOException("Could not establish a guarded path from PackageRoot to target.");

            var handles = new List<SafeFileHandle>();
            try
            {
                while (directories.Count > 0)
                {
                    string directory = directories.Pop();
                    handles.Add(OpenAndValidate(directory, true, "Package directory"));
                }
                if (!targetIsDirectory)
                    handles.Add(OpenAndValidate(target, false, "Package file"));
                return new CatalogPathGuard(handles);
            }
            catch
            {
                for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose();
                throw;
            }
        }
    }
}
'@
}

function Assert-SisqualCatalogPathHasNoReparsePoint {
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

function Assert-SisqualCatalogLocalFixedRoot {
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot
    )

    if (-not [System.IO.Path]::IsPathRooted($PackageRoot)) {
        throw 'PackageRoot must be an absolute local path.'
    }
    if ($PackageRoot.StartsWith('\\', [StringComparison]::Ordinal) -or
        $PackageRoot.StartsWith('//', [StringComparison]::Ordinal) -or
        $PackageRoot.StartsWith('\\?\', [StringComparison]::Ordinal) -or
        $PackageRoot.StartsWith('\\.\', [StringComparison]::Ordinal)) {
        throw 'PackageRoot must be an absolute local fixed-drive path.'
    }

    $root = [System.IO.Path]::GetFullPath($PackageRoot)
    $driveRoot = [System.IO.Path]::GetPathRoot($root)
    if ([string]::IsNullOrWhiteSpace($driveRoot)) {
        throw 'PackageRoot drive could not be resolved.'
    }
    $drive = [System.IO.DriveInfo]::new($driveRoot)
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
        throw "PackageRoot must be on a fixed local drive; detected $($drive.DriveType)."
    }
    return $root
}

function Resolve-SisqualCatalogPackageMember {
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot,
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Label,
        [ValidateSet('File','Directory')]
        [string]$PathType,
        [switch]$AllowMissing
    )

    if ([string]::IsNullOrWhiteSpace($PackageRoot) -or [string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label and PackageRoot cannot be empty."
    }

    $root = Assert-SisqualCatalogLocalFixedRoot -PackageRoot $PackageRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw "PackageRoot does not exist: $root"
    }
    Assert-SisqualCatalogPathHasNoReparsePoint -Path $root -Label 'PackageRoot'

    $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path $root $Path))
    }

    if ($candidate.StartsWith('\\', [StringComparison]::Ordinal) -or
        $candidate.StartsWith('//', [StringComparison]::Ordinal) -or
        $candidate.StartsWith('\\?\', [StringComparison]::Ordinal) -or
        $candidate.StartsWith('\\.\', [StringComparison]::Ordinal)) {
        throw "$Label must be a local path."
    }

    # The configured PackageRoot spelling is the exact security boundary. This deliberately
    # rejects differently-cased aliases so per-directory NTFS case sensitivity cannot turn a
    # sibling tree into an apparently contained provider/catalog path.
    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = $root.TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $candidate.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw "$Label is outside PackageRoot: $candidate"
    }

    Assert-SisqualCatalogPathHasNoReparsePoint -Path $candidate -Label $Label

    if (-not $AllowMissing) {
        $ok = if ($PathType -eq 'File') {
            Test-Path -LiteralPath $candidate -PathType Leaf
        }
        else {
            Test-Path -LiteralPath $candidate -PathType Container
        }
        if (-not $ok) {
            throw "$Label does not exist as a ${PathType}: $candidate"
        }
    }

    return $candidate
}

function Find-SisqualCatalogProviderFile {
    param(
        [Parameter(Mandatory)]
        [string]$ProviderRoot,
        [Parameter(Mandatory)]
        [string]$Name
    )

    $items = @(Get-ChildItem -LiteralPath $ProviderRoot -Recurse -File -Filter $Name -ErrorAction Stop)
    if ($items.Count -ne 1) {
        throw "Expected exactly one $Name below provider root; found $($items.Count)."
    }
    Assert-SisqualCatalogPathHasNoReparsePoint -Path $items[0].FullName -Label $Name
    return $items[0].FullName
}

function Invoke-SisqualCatalogScalar {
    param(
        [Parameter(Mandatory)]
        $Connection,
        [Parameter(Mandatory)]
        [string]$Sql
    )

    $command = $Connection.CreateCommand()
    try {
        $command.CommandText = $Sql
        return $command.ExecuteScalar()
    }
    finally {
        $command.Dispose()
    }
}

function Get-SisqualRuntimeSqliteDefaults {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ProviderVersion = $script:ExpectedProviderVersion
        NativeSqliteVersion = $script:ExpectedNativeSqliteVersion
        ConnectionMode = 'ReadOnly'
        CacheMode = 'Private'
        Pooling = $false
    }
}

function Initialize-SisqualRuntimeSqliteProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageRoot,
        [Parameter(Mandatory)]
        [string]$ProviderRoot
    )

    $resolvedProviderRoot = Resolve-SisqualCatalogPackageMember -PackageRoot $PackageRoot -Path $ProviderRoot -Label 'ProviderRoot' -PathType Directory
    $resolvedPackageRoot = Assert-SisqualCatalogLocalFixedRoot -PackageRoot $PackageRoot

    if ($null -ne $script:ProviderState) {
        if (-not $script:ProviderState.PackageRoot.Equals($resolvedPackageRoot, [StringComparison]::Ordinal) -or
            -not $script:ProviderState.ProviderRoot.Equals($resolvedProviderRoot, [StringComparison]::Ordinal)) {
            throw 'SQLite provider is already initialized from a different package path in this process.'
        }
        return $script:ProviderState
    }

    $managedNames = @(
        'SQLitePCLRaw.core.dll',
        'SQLitePCLRaw.provider.e_sqlite3.dll',
        'SQLitePCLRaw.batteries_v2.dll',
        'Microsoft.Data.Sqlite.dll'
    )

    $managed = [ordered]@{}
    foreach ($name in $managedNames) {
        $managed[$name] = Find-SisqualCatalogProviderFile -ProviderRoot $resolvedProviderRoot -Name $name
    }
    $native = Find-SisqualCatalogProviderFile -ProviderRoot $resolvedProviderRoot -Name 'e_sqlite3.dll'

    $guards = [System.Collections.Generic.List[System.IDisposable]]::new()
    try {
        $guards.Add([Sisqual.Runtime.CatalogPathNative]::GuardPackageMember($resolvedPackageRoot, $resolvedProviderRoot, $true))
        foreach ($path in @($managed.Values) + @($native)) {
            $guards.Add([Sisqual.Runtime.CatalogPathNative]::GuardPackageMember($resolvedPackageRoot, [string]$path, $false))
        }

        $nativeHandle = [System.Runtime.InteropServices.NativeLibrary]::Load($native)
        if ($nativeHandle -eq [IntPtr]::Zero) {
            throw 'Failed to load the pinned native SQLite library.'
        }

        foreach ($name in $managedNames) {
            Add-Type -Path $managed[$name] -ErrorAction Stop
        }
        [SQLitePCL.Batteries_V2]::Init()

        $providerFile = Get-Item -LiteralPath $managed['Microsoft.Data.Sqlite.dll']
        $providerVersion = [string]$providerFile.VersionInfo.ProductVersion
        if (-not $providerVersion.Equals($script:ExpectedProviderVersion, [StringComparison]::Ordinal)) {
            throw "Microsoft.Data.Sqlite version mismatch. Expected $($script:ExpectedProviderVersion), got $providerVersion."
        }

        $script:ProviderState = [pscustomobject]@{
            PackageRoot = $resolvedPackageRoot
            ProviderRoot = $resolvedProviderRoot
            ProviderVersion = $script:ExpectedProviderVersion
            NativeSqliteVersion = $script:ExpectedNativeSqliteVersion
            NativeLibraryPath = $native
            NativeLibraryHandle = $nativeHandle
            AssemblyPath = $managed['Microsoft.Data.Sqlite.dll']
            PathGuards = @($guards)
        }
        return $script:ProviderState
    }
    catch {
        foreach ($guard in @($guards)) {
            try { $guard.Dispose() } catch {}
        }
        throw
    }
}

function Open-SisqualRuntimeCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath,
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9_-]{1,60}$')]
        [string]$ExpectedServerCode,
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int]$ExpectedSchemaVersion,
        [Parameter(Mandatory)]
        [ValidateSet('conversion-tool','manual-edit-sealed','build')]
        [string]$ExpectedOrigin,
        [string]$ExpectedOriginReference
    )

    if ($null -eq $script:ProviderState) {
        throw 'SQLite provider has not been initialized.'
    }

    $fullPath = Resolve-SisqualCatalogPackageMember -PackageRoot $script:ProviderState.PackageRoot -Path $CatalogPath -Label 'CatalogPath' -PathType File
    $expectedName = 'catalog-{0}.db' -f $ExpectedServerCode
    if ([System.IO.Path]::GetFileName($fullPath) -cne $expectedName) {
        throw "Catalog file name mismatch. Expected $expectedName."
    }

    $pathGuard = [Sisqual.Runtime.CatalogPathNative]::GuardPackageMember($script:ProviderState.PackageRoot, $fullPath, $false)
    $builder = [Microsoft.Data.Sqlite.SqliteConnectionStringBuilder]::new()
    $builder.DataSource = $fullPath
    $builder.Mode = [Microsoft.Data.Sqlite.SqliteOpenMode]::ReadOnly
    $builder.Cache = [Microsoft.Data.Sqlite.SqliteCacheMode]::Private
    $builder.Pooling = $false
    $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($builder.ConnectionString)

    try {
        $connection.Open()

        $command = $connection.CreateCommand()
        try {
            $command.CommandText = 'PRAGMA query_only = ON;'
            [void]$command.ExecuteNonQuery()
        }
        finally {
            $command.Dispose()
        }

        $queryOnly = [int64](Invoke-SisqualCatalogScalar -Connection $connection -Sql 'PRAGMA query_only;')
        if ($queryOnly -ne 1) {
            throw 'SQLite query_only did not remain enabled.'
        }

        $nativeVersion = [string](Invoke-SisqualCatalogScalar -Connection $connection -Sql 'SELECT sqlite_version();')
        if ($nativeVersion -cne $script:ExpectedNativeSqliteVersion) {
            throw "Native SQLite version mismatch. Expected $($script:ExpectedNativeSqliteVersion), got $nativeVersion."
        }

        $integrity = [string](Invoke-SisqualCatalogScalar -Connection $connection -Sql 'PRAGMA integrity_check;')
        if ($integrity -cne 'ok') {
            throw "Catalog integrity_check failed: $integrity"
        }

        $rowCount = [int64](Invoke-SisqualCatalogScalar -Connection $connection -Sql 'SELECT COUNT(*) FROM catalog_meta;')
        if ($rowCount -ne 1) {
            throw "catalog_meta must contain exactly one row; found $rowCount."
        }

        $command = $connection.CreateCommand()
        try {
            $command.CommandText = @'
SELECT meta_id, schema_version, server_code, source_kind, source_reference, built_at_utc, cut_rule_version
FROM catalog_meta
WHERE meta_id = $metaId;
'@
            $parameter = $command.CreateParameter()
            $parameter.ParameterName = '$metaId'
            $parameter.Value = 1
            [void]$command.Parameters.Add($parameter)
            $reader = $command.ExecuteReader()
            try {
                if (-not $reader.Read()) {
                    throw 'catalog_meta row with meta_id=1 was not found.'
                }
                $metadata = [pscustomobject]@{
                    MetaId = [int64]$reader.GetInt64(0)
                    SchemaVersion = [int64]$reader.GetInt64(1)
                    ServerCode = [string]$reader.GetString(2)
                    SourceKind = [string]$reader.GetString(3)
                    SourceReference = [string]$reader.GetString(4)
                    BuiltAtUtc = [string]$reader.GetString(5)
                    CutRuleVersion = [int64]$reader.GetInt64(6)
                }
                if ($reader.Read()) {
                    throw 'catalog_meta returned more than one meta_id=1 row.'
                }
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $command.Dispose()
        }

        if ($metadata.MetaId -ne 1) {
            throw 'catalog_meta.meta_id must be 1.'
        }
        if ($metadata.SchemaVersion -ne $ExpectedSchemaVersion) {
            throw "Catalog schema version mismatch. Expected $ExpectedSchemaVersion, got $($metadata.SchemaVersion)."
        }
        if (-not $metadata.ServerCode.Equals($ExpectedServerCode, [StringComparison]::Ordinal)) {
            throw "Catalog ServerCode mismatch. Expected $ExpectedServerCode, got $($metadata.ServerCode)."
        }
        if (-not $metadata.SourceKind.Equals($ExpectedOrigin, [StringComparison]::Ordinal)) {
            throw "Catalog source kind mismatch. Expected $ExpectedOrigin, got $($metadata.SourceKind)."
        }
        if (-not [string]::IsNullOrEmpty($ExpectedOriginReference) -and
            -not $metadata.SourceReference.Equals($ExpectedOriginReference, [StringComparison]::Ordinal)) {
            throw 'Catalog source reference does not match the verified manifest value.'
        }
        if ($metadata.SourceReference.Length -gt 200 -or $metadata.SourceReference -notmatch '^[\x20-\x7E]*$') {
            throw 'Catalog source_reference must be printable ASCII and no longer than 200 characters.'
        }

        $builtAt = [datetime]::MinValue
        $builtAtOk = [datetime]::TryParseExact(
            $metadata.BuiltAtUtc,
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$builtAt
        )
        if (-not $builtAtOk -or $builtAt.Kind -ne [DateTimeKind]::Utc) {
            throw 'Catalog built_at_utc is not the required UTC second-precision format.'
        }

        return [pscustomobject]@{
            PSTypeName = 'Sisqual.Runtime.CatalogSession'
            CatalogPath = $fullPath
            Connection = $connection
            Metadata = $metadata
            NativeSqliteVersion = $nativeVersion
            QueryOnly = $true
            OpenedAtUtc = [datetime]::UtcNow
            PathGuard = $pathGuard
        }
    }
    catch {
        $connection.Dispose()
        $pathGuard.Dispose()
        throw
    }
}

function Close-SisqualRuntimeCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Session
    )

    if ($null -ne $Session.Connection) {
        $Session.Connection.Dispose()
    }
    if ($null -ne $Session.PSObject.Properties['PathGuard'] -and $null -ne $Session.PathGuard) {
        $Session.PathGuard.Dispose()
    }
}

Export-ModuleMember -Function Get-SisqualRuntimeSqliteDefaults, Initialize-SisqualRuntimeSqliteProvider, Open-SisqualRuntimeCatalog, Close-SisqualRuntimeCatalog
