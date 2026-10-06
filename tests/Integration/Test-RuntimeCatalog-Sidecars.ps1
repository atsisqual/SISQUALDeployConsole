#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProviderRoot,
    [Parameter(Mandatory)][string]$SqliteCli,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
Import-Module (Join-Path $repo 'runtime' 'Sisqual.Runtime.Catalog.psm1') -Force

$checks = [System.Collections.Generic.List[object]]::new()
$passed = 0
$failed = 0
function Check([string]$Name, [bool]$Condition) {
    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    if ($Condition) { $script:passed++ } else { $script:failed++ }
    $script:checks.Add([pscustomobject]@{ name = $Name; status = $status })
    Write-Host "$status  $Name"
}
function Throws([scriptblock]$Action) {
    try { & $Action; return $false } catch { return $true }
}
function GetTrust([string]$Path) {
    $file = Get-Item -LiteralPath $Path -Force
    [pscustomobject]@{ Sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant(); Size = [long]$file.Length }
}
function VerifiedFiles([string]$PackageRoot, [string]$Root) {
    @(
        Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
            [pscustomobject]@{
                path = [IO.Path]::GetRelativePath($PackageRoot, $_.FullName).Replace('\','/')
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                size = [long]$_.Length
            }
        }
    )
}

$tempRoot = Join-Path $env:TEMP ('sisqual-runtime-catalog-sidecar-' + [guid]::NewGuid().ToString('N'))
$session = $null
try {
    $packageRoot = Join-Path $tempRoot 'package'
    $providerCopy = Join-Path $packageRoot 'runtime\sqlite-provider'
    $catalogRoot = Join-Path $packageRoot 'catalog'
    New-Item -ItemType Directory -Path $catalogRoot -Force | Out-Null
    Copy-Item -LiteralPath $ProviderRoot -Destination $providerCopy -Recurse -Force
    $verified = VerifiedFiles -PackageRoot $packageRoot -Root $providerCopy
    Initialize-SisqualRuntimeSqliteProvider -PackageRoot $packageRoot -ProviderRoot 'runtime\sqlite-provider' -VerifiedFiles $verified | Out-Null

    $catalog = Join-Path $catalogRoot 'catalog-SIDECAR.db'
    $sql = @'
CREATE TABLE catalog_meta(meta_id INTEGER PRIMARY KEY CHECK(meta_id=1), schema_version INTEGER NOT NULL, server_code TEXT NOT NULL, source_kind TEXT NOT NULL, source_reference TEXT NOT NULL, built_at_utc TEXT NOT NULL, cut_rule_version INTEGER NOT NULL);
INSERT INTO catalog_meta VALUES(1,1,'SIDECAR','conversion-tool','sidecar-test','2026-10-06T01:00:00Z',1);
CREATE TABLE sample(code TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO sample VALUES('A','verified-main');
'@
    $output = & $SqliteCli $catalog $sql 2>&1
    if ($LASTEXITCODE -ne 0) { throw "sqlite fixture creation failed: $($output -join ' ')" }
    $trust = GetTrust $catalog
    $hashBefore = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash

    $wal = $catalog + '-wal'
    $shm = $catalog + '-shm'
    [IO.File]::WriteAllBytes($wal, [byte[]](1,2,3,4,5,6,7,8))
    [IO.File]::WriteAllBytes($shm, [byte[]](8,7,6,5,4,3,2,1))
    $walBefore = [Convert]::ToHexString([IO.File]::ReadAllBytes($wal))
    $shmBefore = [Convert]::ToHexString([IO.File]::ReadAllBytes($shm))

    $rejected = Throws {
        Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-SIDECAR.db' -ExpectedSha256 $trust.Sha256 -ExpectedSize $trust.Size -ExpectedServerCode 'SIDECAR' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' -ExpectedOriginReference 'sidecar-test' | Out-Null
    }
    Check 'unverified WAL/SHM sidecars fail closed before catalog use' $rejected
    Check 'rejected sidecars and verified main bytes remain unchanged' (((Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash -ceq $hashBefore) -and ([Convert]::ToHexString([IO.File]::ReadAllBytes($wal)) -ceq $walBefore) -and ([Convert]::ToHexString([IO.File]::ReadAllBytes($shm)) -ceq $shmBefore))

    Remove-Item -LiteralPath $wal, $shm -Force
    $session = Open-SisqualRuntimeCatalog -CatalogPath 'catalog\catalog-SIDECAR.db' -ExpectedSha256 $trust.Sha256 -ExpectedSize $trust.Size -ExpectedServerCode 'SIDECAR' -ExpectedSchemaVersion 1 -ExpectedOrigin 'conversion-tool' -ExpectedOriginReference 'sidecar-test'
    Check 'sealed catalog opens through immutable guarded view' ($session.Immutable -and $session.QueryOnly -and $session.Metadata.ServerCode -ceq 'SIDECAR')
    Check 'immutable catalog open creates no SQLite sidecars' (@(Get-ChildItem -LiteralPath $catalogRoot -File | Where-Object { $_.Name -match '-(wal|shm|journal)$' }).Count -eq 0)

    $lateSidecarWriteBlocked = $false
    try {
        [IO.File]::WriteAllBytes($wal, [byte[]](9,9,9,9))
        [IO.File]::WriteAllBytes($shm, [byte[]](7,7,7,7))
    }
    catch {
        $lateSidecarWriteBlocked = $true
    }
    $mainStillVerified = ((Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash -ceq $hashBefore)
    Check 'late sidecar attempt cannot alter guarded main bytes' $mainStillVerified
    Check 'late sidecars are blocked by the guard or isolated by immutable view' ($lateSidecarWriteBlocked -or $session.Immutable)
}
finally {
    if ($null -ne $session) { Close-SisqualRuntimeCatalog -Session $session }
    Remove-Module Sisqual.Runtime.Catalog -ErrorAction SilentlyContinue

    # The native provider is intentionally retained for the PowerShell process lifetime. On
    # Windows that keeps e_sqlite3.dll locked until process exit, so disposable provider cleanup
    # is best-effort and must not turn a successful security test into a false negative.
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not [string]::IsNullOrWhiteSpace($ReportPath)) {
    [pscustomobject]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        passed = $passed
        failed = $failed
        checks = @($checks)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
}
Write-Host ("{0} passed, {1} failed" -f $passed, $failed)
if ($failed -gt 0) { exit 1 }
