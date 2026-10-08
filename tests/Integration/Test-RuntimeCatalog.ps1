#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProviderRoot,
    [Parameter(Mandatory)]
    [string]$SqliteCli,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modulePath = Join-Path $repo 'runtime' 'Sisqual.Runtime.Catalog.psm1'
Import-Module $modulePath -Force

$script:Passed = 0
$script:Failed = 0
$script:Checks = [System.Collections.Generic.List[object]]::new()

function Test-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Condition
    )

    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    if ($Condition) { $script:Passed++ } else { $script:Failed++ }
    $script:Checks.Add([pscustomobject]@{ name = $Name; status = $status })
    Write-Host "$status  $Name"
}

function Test-Throws {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    $threw = $false
    try { & $Action } catch { $threw = $true }
    Test-Check -Name $Name -Condition $threw
}

function ConvertTo-SqliteLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-FileTrust {
    param([Parameter(Mandatory)][string]$Path)

    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    return [pscustomobject]@{
        Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        Size = [long]$file.Length
    }
}

function Get-VerifiedPackageFiles {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$Root
    )

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction Stop)) {
        $entries.Add([pscustomobject]@{
            path = [IO.Path]::GetRelativePath($PackageRoot, $file.FullName).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            size = [long]$file.Length
        })
    }
    return @($entries)
}

function New-CatalogFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ServerCode,
        [int]$SchemaVersion = 1,
        [string]$SourceKind = 'conversion-tool',
        [string]$SourceReference = 'test-run',
        [string]$BuiltAtUtc = '2026-10-06T01:00:00Z',
        [int]$CutRuleVersion = 1,
        [switch]$TwoMetaRows
    )

    $metaConstraint = if ($TwoMetaRows) { '' } else { ' PRIMARY KEY CHECK (meta_id = 1)' }
    $sql = @"
CREATE TABLE catalog_meta(
  meta_id INTEGER$metaConstraint,
  schema_version INTEGER NOT NULL,
  server_code TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_reference TEXT NOT NULL,
  built_at_utc TEXT NOT NULL,
  cut_rule_version INTEGER NOT NULL
);
INSERT INTO catalog_meta(meta_id,schema_version,server_code,source_kind,source_reference,built_at_utc,cut_rule_version)
VALUES(1,$SchemaVersion,$(ConvertTo-SqliteLiteral $ServerCode),$(ConvertTo-SqliteLiteral $SourceKind),$(ConvertTo-SqliteLiteral $SourceReference),$(ConvertTo-SqliteLiteral $BuiltAtUtc),$CutRuleVersion);
CREATE TABLE dbo_ManagedServer(MachineName TEXT NOT NULL);
INSERT INTO dbo_ManagedServer(MachineName) VALUES('CATALOG-MACHINE');
CREATE TABLE dbo_ManagedInstance(InstanceCode TEXT NOT NULL PRIMARY KEY, IsEnabled INTEGER NOT NULL);
INSERT INTO dbo_ManagedInstance(InstanceCode, IsEnabled) VALUES('PT01', 1), ('PT02', 0);
CREATE TABLE sample(code TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO sample(code,value) VALUES('A','alpha'),('B','beta');
"@
    if ($TwoMetaRows) {
        $sql += "`nINSERT INTO catalog_meta(meta_id,schema_version,server_code,source_kind,source_reference,built_at_utc,cut_rule_version) VALUES(2,$SchemaVersion,$(ConvertTo-SqliteLiteral $ServerCode),$(ConvertTo-SqliteLiteral $SourceKind),'second','2026-10-06T01:00:00Z',$CutRuleVersion);"
    }

    $output = & $SqliteCli $Path $sql 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sqlite3 fixture creation failed: $($output -join ' ')"
    }
}

$tempRoot = Join-Path $env:TEMP ('sisqual-runtime-catalog-' + [guid]::NewGuid().ToString('N'))
$outsideRoot = Join-Path $env:TEMP ('sisqual-runtime-catalog-outside-' + [guid]::NewGuid().ToString('N'))
$openSessions = [System.Collections.Generic.List[object]]::new()
try {
    New-Item -ItemType Directory -Path $tempRoot, $outsideRoot -Force | Out-Null
    $packageRoot = Join-Path $tempRoot 'package'
    $providerCopy = Join-Path $packageRoot 'runtime\sqlite-provider'
    $catalogRoot = Join-Path $packageRoot 'catalog'
    New-Item -ItemType Directory -Path $packageRoot, $catalogRoot -Force | Out-Null
    Copy-Item -LiteralPath $ProviderRoot -Destination $providerCopy -Recurse -Force
    $verifiedProviderFiles = Get-VerifiedPackageFiles -PackageRoot $packageRoot -Root $providerCopy

    $defaults = Get-SisqualRuntimeSqliteDefaults
    Test-Check 'provider version pin is 10.0.12' ($defaults.ProviderVersion -ceq '10.0.12')
    Test-Check 'native runtime SQLite pin is 3.53.3' ($defaults.NativeSqliteVersion -ceq '3.53.3')
    Test-Check 'factory defaults are read-only private-cache' ($defaults.ConnectionMode -ceq 'ReadOnly' -and $defaults.CacheMode -ceq 'Private' -and -not $defaults.Pooling)

    Test-Throws 'relative PackageRoot is rejected before normalization' {
        Initialize-SisqualRuntimeSqliteProvider -PackageRoot '.' -ProviderRoot 'runtime\sqlite-provider' -VerifiedFiles $verifiedProviderFiles | Out-Null
    }
    Test-Throws 'provider path outside package is rejected' {
        Initialize-SisqualRuntimeSqliteProvider -PackageRoot $packageRoot -ProviderRoot $ProviderRoot -VerifiedFiles $verifiedProviderFiles | Out-Null
    }
    $caseVariantProvider = $providerCopy.Replace('\package\', '\PACKAGE\')
    Test-Throws 'package containment rejects case-distinct boundary spelling' {
        Initialize-SisqualRuntimeSqliteProvider -PackageRoot $packageRoot -ProviderRoot $caseVariantProvider -VerifiedFiles $verifiedProviderFiles | Out-Null
    }

    $provider = Initialize-SisqualRuntimeSqliteProvider -PackageRoot $packageRoot -ProviderRoot 'runtime\sqlite-provider' -VerifiedFiles $verifiedProviderFiles
    Test-Check 'copied provider payload initializes from package tree' ($provider.ProviderVersion -ceq '10.0.12' -and $provider.ProviderRoot -ceq [IO.Path]::GetFullPath($providerCopy))
    Test-Check 'provider files are rebound to verified manifest bytes' ($provider.VerifiedFiles.Count -ge 5)

    $providerRenameBlocked = $false
    try {
        Rename-Item -LiteralPath $providerCopy -NewName 'sqlite-provider-moved' -ErrorAction Stop
    }
    catch {
        $providerRenameBlocked = $true
    }
    Test-Check 'provider path guard blocks directory replacement after initialization' $providerRenameBlocked

    $providerWriteBlocked = $false
    $providerWriteStream = $null
    try {
        $providerWriteStream = [IO.File]::Open($provider.AssemblyPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    }
    catch {
        $providerWriteBlocked = $true
    }
    finally {
        if ($null -ne $providerWriteStream) { $providerWriteStream.Dispose() }
    }
    Test-Check 'provider file guard denies in-place write opens' $providerWriteBlocked

    $validPath = Join-Path $catalogRoot 'catalog-DEMO.db'
    New-CatalogFixture -Path $validPath -ServerCode 'DEMO'
    $validTrust = Get-FileTrust -Path $validPath
    $hashBefore = (Get-FileHash -LiteralPath $validPath -Algorithm SHA256).Hash

    Test-Throws 'catalog SHA-256 mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 ('0' * 64) -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }
    Test-Throws 'catalog size mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize ($validTrust.Size + 1) -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }

    $session = Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' -ExpectedOriginReference 'test-run'
    $openSessions.Add($session)
    Test-Check 'valid catalog opens with query_only enabled' ($session.QueryOnly -and $session.CatalogPath -ceq [IO.Path]::GetFullPath($validPath))
    Test-Check 'native SQLite version is exact' ($session.NativeSqliteVersion -ceq '3.53.3')
    Test-Check 'catalog metadata is exact and case-sensitive' ($session.Metadata.ServerCode -ceq 'DEMO' -and $session.Metadata.SourceKind -ceq 'conversion-tool' -and $session.Metadata.SchemaVersion -eq 1)
    Test-Check 'catalog session records guarded trust evidence' ($session.VerifiedSha256 -ceq $validTrust.Sha256 -and $session.VerifiedSize -eq $validTrust.Size)
    Test-Check 'catalog session does not expose raw SQLite connection' ($null -eq $session.PSObject.Properties['Connection'])
    Test-Check 'active verified catalog session reads machine ownership from dbo_ManagedServer' ((Get-SisqualRuntimeCatalogMachineName -Session $session) -ceq 'CATALOG-MACHINE')
    Test-Check 'active verified catalog session reads an enabled instance' (((Get-SisqualRuntimeCatalogInstance -Session $session -InstanceCode 'PT01').IsEnabled) -eq 1)
    Test-Check 'active verified catalog session reads a disabled instance' (((Get-SisqualRuntimeCatalogInstance -Session $session -InstanceCode 'PT02').IsEnabled) -eq 0)
    Test-Check 'an instance that is not in the catalog is null' ($null -eq (Get-SisqualRuntimeCatalogInstance -Session $session -InstanceCode 'PT99'))
    Test-Check 'the instance code is a bound parameter (an injection attempt matches nothing)' ($null -eq (Get-SisqualRuntimeCatalogInstance -Session $session -InstanceCode 'PT01'' OR ''1''=''1'))
    Test-Throws 'forged catalog session cannot read instances' { Get-SisqualRuntimeCatalogInstance -Session ([pscustomobject]@{ SessionId = [guid]::NewGuid().ToString('N') }) -InstanceCode 'PT01' }
    Test-Throws 'forged catalog session cannot read machine ownership' { Get-SisqualRuntimeCatalogMachineName -Session ([pscustomobject]@{ SessionId = [guid]::NewGuid().ToString('N') }) | Out-Null }

    $catalogRenameBlocked = $false
    try {
        Rename-Item -LiteralPath $catalogRoot -NewName 'catalog-moved' -ErrorAction Stop
    }
    catch {
        $catalogRenameBlocked = $true
    }
    Test-Check 'catalog path guard blocks directory replacement while session is open' $catalogRenameBlocked

    $catalogWriteBlocked = $false
    $catalogWriteStream = $null
    try {
        $catalogWriteStream = [IO.File]::Open($validPath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    }
    catch {
        $catalogWriteBlocked = $true
    }
    finally {
        if ($null -ne $catalogWriteStream) { $catalogWriteStream.Dispose() }
    }
    Test-Check 'catalog file guard denies in-place write opens while session is active' $catalogWriteBlocked

    Close-SisqualRuntimeCatalog -Session $session
    $openSessions.Remove($session) | Out-Null

    $hashAfter = (Get-FileHash -LiteralPath $validPath -Algorithm SHA256).Hash
    Test-Check 'catalog bytes remain unchanged' ($hashAfter -ceq $hashBefore)
    $sidecars = @(Get-ChildItem -LiteralPath $catalogRoot -File | Where-Object { $_.Name -match '-(wal|shm|journal)$' })
    Test-Check 'read-only factory creates no SQLite sidecars' ($sidecars.Count -eq 0)

    $missingPath = Join-Path $catalogRoot 'catalog-MISSING.db'
    Test-Throws 'missing catalog is rejected without creation' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-MISSING.db' -ExpectedSha256 ('0' * 64) -ExpectedSize 0 -ExpectedServerCode 'MISSING' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }
    Test-Check 'missing catalog was not created' (-not (Test-Path -LiteralPath $missingPath))

    Test-Throws 'catalog path outside package is rejected' {
        Open-SisqualRuntimeCatalog -CatalogPath (Join-Path $outsideRoot 'catalog-OUT.db') -ExpectedSha256 ('0' * 64) -ExpectedSize 0 -ExpectedServerCode 'OUT' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }

    $otherPath = Join-Path $catalogRoot 'catalog-OTHER.db'
    Copy-Item -LiteralPath $validPath -Destination $otherPath
    $otherTrust = Get-FileTrust -Path $otherPath
    Test-Throws 'metadata ServerCode mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-OTHER.db' -ExpectedSha256 $otherTrust.Sha256 -ExpectedSize $otherTrust.Size -ExpectedServerCode 'OTHER' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }
    Test-Throws 'metadata schema version mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 2 -ExpectedOrigin 'conversion-tool' | Out-Null
    }
    Test-Throws 'metadata source kind mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'build' | Out-Null
    }
    Test-Throws 'metadata source reference mismatch fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' -ExpectedOriginReference 'different' | Out-Null
    }

    $badTimePath = Join-Path $catalogRoot 'catalog-BADTIME.db'
    New-CatalogFixture -Path $badTimePath -ServerCode 'BADTIME' -BuiltAtUtc '2026-10-06 01:00:00'
    $badTimeTrust = Get-FileTrust -Path $badTimePath
    Test-Throws 'malformed built_at_utc fails closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-BADTIME.db' -ExpectedSha256 $badTimeTrust.Sha256 -ExpectedSize $badTimeTrust.Size -ExpectedServerCode 'BADTIME' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }

    $multiPath = Join-Path $catalogRoot 'catalog-MULTI.db'
    New-CatalogFixture -Path $multiPath -ServerCode 'MULTI' -TwoMetaRows
    $multiTrust = Get-FileTrust -Path $multiPath
    Test-Throws 'multiple catalog_meta rows fail closed' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-MULTI.db' -ExpectedSha256 $multiTrust.Sha256 -ExpectedSize $multiTrust.Size -ExpectedServerCode 'MULTI' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }

    $junctionCatalogRoot = Join-Path $packageRoot 'catalog-link'
    $outsideCatalogPath = Join-Path $outsideRoot 'catalog-JUNCTION.db'
    New-CatalogFixture -Path $outsideCatalogPath -ServerCode 'JUNCTION'
    $outsideCatalogTrust = Get-FileTrust -Path $outsideCatalogPath
    New-Item -ItemType Junction -Path $junctionCatalogRoot -Target $outsideRoot -Force | Out-Null
    Test-Throws 'catalog path through junction is rejected' {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog-link\catalog-JUNCTION.db' -ExpectedSha256 $outsideCatalogTrust.Sha256 -ExpectedSize $outsideCatalogTrust.Size -ExpectedServerCode 'JUNCTION' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' | Out-Null
    }
    Remove-Item -LiteralPath $junctionCatalogRoot -Force

    $parallelPass = $true
    try {
        for ($i = 0; $i -lt 20; $i++) {
            $parallel = Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-DEMO.db' -ExpectedSha256 $validTrust.Sha256 -ExpectedSize $validTrust.Size -ExpectedServerCode 'DEMO' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool'
            $openSessions.Add($parallel)
        }
        $parallelPass = ($openSessions.Count -eq 20)
    }
    catch {
        $parallelPass = $false
    }
    finally {
        foreach ($parallel in @($openSessions)) {
            Close-SisqualRuntimeCatalog -Session $parallel
        }
        $openSessions.Clear()
    }
    Test-Check 'twenty simultaneous read-only sessions open successfully' $parallelPass

    $hashFinal = (Get-FileHash -LiteralPath $validPath -Algorithm SHA256).Hash
    Test-Check 'catalog stays byte-identical after repeated sessions' ($hashFinal -ceq $hashBefore)
    $finalSidecars = @(Get-ChildItem -LiteralPath $catalogRoot -File | Where-Object { $_.Name -match '-(wal|shm|journal)$' })
    Test-Check 'repeated sessions still create no sidecars' ($finalSidecars.Count -eq 0)
}
finally {
    foreach ($session in @($openSessions)) {
        try { Close-SisqualRuntimeCatalog -Session $session } catch {}
    }
    Remove-Module Sisqual.Runtime.Catalog -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $outsideRoot) {
        Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction Stop
    }

    if (Test-Path -LiteralPath $tempRoot) {
        try {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
        }
        catch {
            # The native e_sqlite3.dll is intentionally loaded for the process lifetime and Windows
            # keeps that DLL locked until pwsh exits. GitHub runner temp cleanup removes the disposable
            # package after this process ends; do not turn a fully passing product test into a failure.
            if ([string]$_.Exception.Message -notmatch 'e_sqlite3\.dll') {
                throw
            }
            Write-Host 'INFO  disposable provider payload remains locked until the test process exits'
        }
    }
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    $report = [ordered]@{
        status = $(if ($script:Failed -eq 0) { 'PASS' } else { 'FAIL' })
        powerShell = $PSVersionTable.PSVersion.ToString()
        providerVersion = '10.0.12'
        nativeSqliteVersion = '3.53.3'
        sqliteCli = (& $SqliteCli --version | Select-Object -First 1)
        passed = $script:Passed
        failed = $script:Failed
        checks = @($script:Checks)
    }
    $json = $report | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), $json + "`n", [Text.UTF8Encoding]::new($false))
}

if ($script:Failed -gt 0) { exit 1 }
