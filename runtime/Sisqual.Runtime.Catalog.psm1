#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep the reviewed provider/path-guard implementation byte-identical in the core file.
# This wrapper only hardens catalog opening against unverified SQLite sidecars.
. (Join-Path $PSScriptRoot 'Sisqual.Runtime.Catalog.Core.ps1')

function Assert-SisqualCatalogSidecarsAbsent {
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath
    )

    foreach ($suffix in @('-wal', '-shm', '-journal')) {
        $sidecar = $CatalogPath + $suffix
        if (Test-Path -LiteralPath $sidecar) {
            throw "Unverified SQLite sidecar is not permitted for a sealed catalog: $([IO.Path]::GetFileName($sidecar))"
        }
    }
}

function Get-SisqualImmutableCatalogUri {
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath
    )

    $absolute = [IO.Path]::GetFullPath($CatalogPath)
    $uri = [Uri]::new($absolute).AbsoluteUri
    if (-not $uri.StartsWith('file:', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Catalog path could not be represented as a local file URI.'
    }
    return $uri + '?immutable=1'
}

function Open-SisqualRuntimeCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CatalogPath,
        [Parameter(Mandatory)]
        [ValidatePattern('^[0-9a-f]{64}$')]
        [string]$ExpectedSha256,
        [Parameter(Mandatory)]
        [long]$ExpectedSize,
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
    if ($ExpectedSize -lt 0) {
        throw 'ExpectedSize cannot be negative.'
    }

    $fullPath = Resolve-SisqualCatalogPackageMember -PackageRoot $script:ProviderState.PackageRoot -Path $CatalogPath -Label 'CatalogPath' -PathType File
    $expectedName = 'catalog-{0}.db' -f $ExpectedServerCode
    if ([IO.Path]::GetFileName($fullPath) -cne $expectedName) {
        throw "Catalog file name mismatch. Expected $expectedName."
    }

    $pathGuard = [Sisqual.Runtime.CatalogPathNative]::GuardPackageMember($script:ProviderState.PackageRoot, $fullPath, $false)
    $connection = $null
    try {
        [void](Assert-SisqualGuardedPackageFile -PackageRoot $script:ProviderState.PackageRoot -FilePath $fullPath -ExpectedSha256 $ExpectedSha256 -ExpectedSize $ExpectedSize)

        # Sealed catalogs are a single authenticated database image. Existing WAL/SHM/journal
        # files are never part of that authenticated image, so reject them. The connection also
        # uses SQLite immutable=1 so a sidecar created after this check cannot become part of the
        # read view while the retained main-file/path guards keep the immutable assertion true.
        Assert-SisqualCatalogSidecarsAbsent -CatalogPath $fullPath
        $immutableUri = Get-SisqualImmutableCatalogUri -CatalogPath $fullPath

        $builder = [Microsoft.Data.Sqlite.SqliteConnectionStringBuilder]::new()
        $builder.DataSource = $immutableUri
        $builder.Mode = [Microsoft.Data.Sqlite.SqliteOpenMode]::ReadOnly
        $builder.Cache = [Microsoft.Data.Sqlite.SqliteCacheMode]::Private
        $builder.Pooling = $false
        $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($builder.ConnectionString)
        $connection.Open()

        # Detect a sidecar created during the open window as a package-hygiene violation as well.
        # immutable=1 prevents it from influencing the opened view; this second check fails closed.
        Assert-SisqualCatalogSidecarsAbsent -CatalogPath $fullPath

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

        $sessionId = [guid]::NewGuid().ToString('N')
        $script:CatalogSessions[$sessionId] = [pscustomobject]@{
            Connection = $connection
            PathGuard = $pathGuard
        }

        $connection = $null
        $pathGuard = $null
        return [pscustomobject]@{
            PSTypeName = 'Sisqual.Runtime.CatalogSession'
            SessionId = $sessionId
            CatalogPath = $fullPath
            Metadata = $metadata
            NativeSqliteVersion = $nativeVersion
            QueryOnly = $true
            Immutable = $true
            OpenedAtUtc = [datetime]::UtcNow
            VerifiedSha256 = $ExpectedSha256
            VerifiedSize = $ExpectedSize
        }
    }
    catch {
        if ($null -ne $connection) {
            $connection.Dispose()
        }
        if ($null -ne $pathGuard) {
            $pathGuard.Dispose()
        }
        throw
    }
}

function Get-SisqualRuntimeCatalogMachineName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Session)

    $sessionIdProperty = $Session.PSObject.Properties['SessionId']
    if ($null -eq $sessionIdProperty -or [string]::IsNullOrWhiteSpace([string]$sessionIdProperty.Value)) { throw 'Catalog session is invalid.' }
    $sessionId = [string]$sessionIdProperty.Value
    if (-not $script:CatalogSessions.ContainsKey($sessionId)) { throw 'Catalog session is not active.' }
    $entry = $script:CatalogSessions[$sessionId]
    $command = $entry.Connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT MachineName FROM dbo_ManagedServer;'
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read() -or $reader.IsDBNull(0)) { throw 'dbo_ManagedServer must contain exactly one MachineName.' }
            $machineName = [string]$reader.GetString(0)
            if ($reader.Read() -or [string]::IsNullOrWhiteSpace($machineName)) { throw 'dbo_ManagedServer must contain exactly one MachineName.' }
            return $machineName
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
}

Export-ModuleMember -Function Get-SisqualRuntimeCatalogMachineName