#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite3 = $env:SQLITE3_PATH
if ([string]::IsNullOrWhiteSpace($sqlite3)) {
    $found = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($found) { $sqlite3 = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($sqlite3) -or -not (Test-Path -LiteralPath $sqlite3 -PathType Leaf)) {
    Write-Host 'sqlite3 was not found. Set SQLITE3_PATH to the pinned sqlite3 executable.'
    exit 2
}

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Test-CatalogConversion.ps1')).Path
. $toolPath -SyncFile 'unused' -CatalogFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failures = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}

function New-C8Database {
    param([string]$Path, [string]$ExtraSql = '')
    $sql = @"
CREATE TABLE cfg_ConfigurationAdapterDefinition (
    AdapterCode TEXT PRIMARY KEY,
    ActionCode TEXT NULL
) STRICT;
CREATE TABLE ops_Action (
    ActionCode TEXT PRIMARY KEY,
    EngineCode TEXT NULL
) STRICT;
CREATE TABLE ops_Engine (
    EngineCode TEXT PRIMARY KEY
) STRICT;
INSERT INTO ops_Engine VALUES ('DATABASE_CONTENT_SYNC');
INSERT INTO ops_Engine VALUES ('WINDOWS_SERVICES');
INSERT INTO ops_Action VALUES ('DATABASE_SETTINGS','DATABASE_CONTENT_SYNC');
INSERT INTO ops_Action VALUES ('WINDOWS_SERVICES','WINDOWS_SERVICES');
INSERT INTO ops_Action VALUES ('READ_ONLY',NULL);
INSERT INTO ops_Action VALUES ('NO_ENGINE','   ');
INSERT INTO cfg_ConfigurationAdapterDefinition VALUES ('DATABASE_SETTING','DATABASE_SETTINGS');
INSERT INTO cfg_ConfigurationAdapterDefinition VALUES ('WINDOWS_SERVICE','WINDOWS_SERVICES');
INSERT INTO cfg_ConfigurationAdapterDefinition VALUES ('LINKS',NULL);
INSERT INTO cfg_ConfigurationAdapterDefinition VALUES ('MANAGED_INSTANCE','');
INSERT INTO cfg_ConfigurationAdapterDefinition VALUES ('WHITESPACE','   ');
$ExtraSql
"@
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Path, $sql))
}

function Invoke-C8Only {
    param([string]$Db)
    $script:Checks.Clear()
    $folder = Split-Path -Parent $Db
    $entry = [pscustomobject]@{ serverCode = 'TEST'; file = (Split-Path -Leaf $Db) }
    Add-C8ActionCrossReferenceChecks -Folder $folder -Sqlite3 $sqlite3 -Entries @($entry)
    return @($script:Checks)
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('c8-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $valid = Join-Path $work 'valid.db'
    New-C8Database -Path $valid
    $checks = Invoke-C8Only -Db $valid
    Assert-That 'C8 tool version is active' ($script:TestToolVersion -eq '0.2.0')
    Assert-That 'valid catalog produces exactly two action-xref checks' ($checks.Count -eq 2 -and @($checks | Where-Object group -ne 'action-xref').Count -eq 0)
    Assert-That 'valid adapter references pass' (@($checks | Where-Object { $_.check -like '*adapter ActionCode*' -and $_.ok }).Count -eq 1)
    Assert-That 'valid action engine references pass' (@($checks | Where-Object { $_.check -like '*EngineCode*' -and $_.ok }).Count -eq 1)
    Assert-That 'NULL, empty and whitespace-only optional references are allowed' (@($checks | Where-Object { -not $_.ok }).Count -eq 0)

    $staleAdapter = Join-Path $work 'stale-adapter.db'
    New-C8Database -Path $staleAdapter -ExtraSql @"
UPDATE cfg_ConfigurationAdapterDefinition SET ActionCode='SETTINGS_SYNC' WHERE AdapterCode='DATABASE_SETTING';
UPDATE cfg_ConfigurationAdapterDefinition SET ActionCode='SERVICE_RECONCILE' WHERE AdapterCode='WINDOWS_SERVICE';
"@
    $checks = Invoke-C8Only -Db $staleAdapter
    $adapterFailure = @($checks | Where-Object { $_.check -like '*adapter ActionCode*' -and -not $_.ok })
    Assert-That 'the two real stale adapter identifiers fail R-043' ($adapterFailure.Count -eq 1 -and $adapterFailure[0].detail -like '*DATABASE_SETTING->SETTINGS_SYNC*' -and $adapterFailure[0].detail -like '*WINDOWS_SERVICE->SERVICE_RECONCILE*')
    Assert-That 'stale adapter metadata does not create a false engine failure' (@($checks | Where-Object { $_.check -like '*EngineCode*' -and -not $_.ok }).Count -eq 0)

    $missingEngine = Join-Path $work 'missing-engine.db'
    New-C8Database -Path $missingEngine -ExtraSql "UPDATE ops_Action SET EngineCode='MISSING_ENGINE' WHERE ActionCode='DATABASE_SETTINGS';"
    $checks = Invoke-C8Only -Db $missingEngine
    Assert-That 'an action that names a missing engine fails the effective engine mapping' (@($checks | Where-Object { $_.check -like '*EngineCode*' -and -not $_.ok -and $_.detail -like '*DATABASE_SETTINGS->MISSING_ENGINE*' }).Count -eq 1)
    Assert-That 'missing engine leaves a valid adapter-to-action reference green' (@($checks | Where-Object { $_.check -like '*adapter ActionCode*' -and -not $_.ok }).Count -eq 0)

    $wrongCase = Join-Path $work 'wrong-case.db'
    New-C8Database -Path $wrongCase -ExtraSql @"
UPDATE cfg_ConfigurationAdapterDefinition SET ActionCode='database_settings' WHERE AdapterCode='DATABASE_SETTING';
UPDATE ops_Action SET EngineCode='windows_services' WHERE ActionCode='WINDOWS_SERVICES';
"@
    $checks = Invoke-C8Only -Db $wrongCase
    Assert-That 'adapter ActionCode comparison is exact and rejects wrong case' (@($checks | Where-Object { $_.check -like '*adapter ActionCode*' -and -not $_.ok -and $_.detail -like '*database_settings*' }).Count -eq 1)
    Assert-That 'engine comparison is exact and rejects wrong case' (@($checks | Where-Object { $_.check -like '*EngineCode*' -and -not $_.ok -and $_.detail -like '*windows_services*' }).Count -eq 1)

    $missingTable = Join-Path $work 'missing-table.db'
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($missingTable, 'CREATE TABLE ops_Action (ActionCode TEXT PRIMARY KEY, EngineCode TEXT NULL) STRICT;'))
    $script:Checks.Clear()
    $entry = [pscustomobject]@{ serverCode = 'TEST'; file = 'missing-table.db' }
    Add-C8ActionCrossReferenceChecks -Folder $work -Sqlite3 $sqlite3 -Entries @($entry)
    Assert-That 'narrow fixtures without all three C8 tables are not misclassified' ($script:Checks.Count -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('C8 action cross-reference tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
