#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExpectedProviderVersion = '10.0.12'
$script:ExpectedNativeSqliteVersion = '3.53.3'
$script:ProviderState = $null

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

    $root = [System.IO.Path]::GetFullPath($PackageRoot)
    if (-not [System.IO.Path]::IsPathRooted($root) -or $root.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'PackageRoot must be an absolute local path.'
    }
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

    if ($candidate.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw "$Label must be a local path."
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $prefix = $root.TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
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
    $resolvedPackageRoot = [System.IO.Path]::GetFullPath($PackageRoot)

    if ($null -ne $script:ProviderState) {
        if (-not $script:ProviderState.PackageRoot.Equals($resolvedPackageRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not $script:ProviderState.ProviderRoot.Equals($resolvedProviderRoot, [StringComparison]::OrdinalIgnoreCase)) {
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
    if (-not $providerVersion.StartsWith($script:ExpectedProviderVersion, [StringComparison]::Ordinal)) {
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
    }
    return $script:ProviderState
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
        }
    }
    catch {
        $connection.Dispose()
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
}

Export-ModuleMember -Function Get-SisqualRuntimeSqliteDefaults, Initialize-SisqualRuntimeSqliteProvider, Open-SisqualRuntimeCatalog, Close-SisqualRuntimeCatalog
