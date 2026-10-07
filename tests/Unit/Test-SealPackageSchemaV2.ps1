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

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Seal-Package.ps1')).Path
. $toolPath -PackageFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failures = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}
function Invoke-Sql {
    param([string]$Db, [string]$Sql)
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Db, $Sql))
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('seal-v2-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $valid = Join-Path $work 'valid-v2.db'
    $sql = @'
CREATE TABLE catalog_meta (
    meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),
    schema_version INTEGER NOT NULL,
    server_code TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_reference TEXT NOT NULL,
    built_at_utc TEXT NOT NULL,
    cut_rule_version INTEGER NOT NULL
) STRICT;
INSERT INTO catalog_meta VALUES (1, 2, 'SRV_A', 'conversion-tool', 'test', '2026-10-06T00:00:00Z', 2);
CREATE TABLE cfg_DatabaseObjectSettingRule (
    ObjectSettingRuleID INTEGER PRIMARY KEY,
    SettingCode TEXT NOT NULL,
    FilterPredicateJson TEXT NOT NULL
) STRICT;
INSERT INTO cfg_DatabaseObjectSettingRule VALUES (1, 'RULE_A', '{"kind":"ALL"}');
PRAGMA user_version = 2;
'@
    Invoke-Sql -Db $valid -Sql $sql
    $validCheck = Test-CatalogFile -Sqlite3 $sqlite3 -Db $valid -ExpectedServerCode 'SRV_A'
    Assert-That 'seal validator supports schema version 2' ($script:SupportedSchemaVersions -contains 2)
    Assert-That 'structurally valid C7 schema v2 catalog passes seal validation' ($validCheck.Problems.Count -eq 0 -and $validCheck.Meta.SchemaVersion -eq 2 -and $validCheck.Meta.CutRuleVersion -eq 2)

    $rawFilter = Join-Path $work 'raw-filter-v2.db'
    $sql = @'
CREATE TABLE catalog_meta (
    meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),
    schema_version INTEGER NOT NULL,
    server_code TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_reference TEXT NOT NULL,
    built_at_utc TEXT NOT NULL,
    cut_rule_version INTEGER NOT NULL
) STRICT;
INSERT INTO catalog_meta VALUES (1, 2, 'SRV_A', 'conversion-tool', 'test', '2026-10-06T00:00:00Z', 2);
CREATE TABLE cfg_DatabaseObjectSettingRule (
    ObjectSettingRuleID INTEGER PRIMARY KEY,
    SettingCode TEXT NOT NULL,
    FilterPredicateJson TEXT NOT NULL,
    FilterClause TEXT
) STRICT;
INSERT INTO cfg_DatabaseObjectSettingRule VALUES (1, 'RULE_A', '{"kind":"ALL"}', NULL);
PRAGMA user_version = 2;
'@
    Invoke-Sql -Db $rawFilter -Sql $sql
    $rawCheck = Test-CatalogFile -Sqlite3 $sqlite3 -Db $rawFilter
    Assert-That 'schema v2 rejects the retired raw FilterClause column' (@($rawCheck.Problems | Where-Object { $_ -like '*must not contain*FilterClause*' }).Count -eq 1)

    $missingPredicate = Join-Path $work 'missing-predicate-v2.db'
    $sql = @'
CREATE TABLE catalog_meta (
    meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),
    schema_version INTEGER NOT NULL,
    server_code TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_reference TEXT NOT NULL,
    built_at_utc TEXT NOT NULL,
    cut_rule_version INTEGER NOT NULL
) STRICT;
INSERT INTO catalog_meta VALUES (1, 2, 'SRV_A', 'conversion-tool', 'test', '2026-10-06T00:00:00Z', 2);
CREATE TABLE cfg_DatabaseObjectSettingRule (
    ObjectSettingRuleID INTEGER PRIMARY KEY,
    SettingCode TEXT NOT NULL
) STRICT;
PRAGMA user_version = 2;
'@
    Invoke-Sql -Db $missingPredicate -Sql $sql
    $missingCheck = Test-CatalogFile -Sqlite3 $sqlite3 -Db $missingPredicate
    Assert-That 'schema v2 rejects a missing FilterPredicateJson column' (@($missingCheck.Problems | Where-Object { $_ -like '*requires*FilterPredicateJson*' }).Count -eq 1)

    $v3 = Join-Path $work 'v3.db'
    $sql = @'
CREATE TABLE catalog_meta (
    meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),
    schema_version INTEGER NOT NULL,
    server_code TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_reference TEXT NOT NULL,
    built_at_utc TEXT NOT NULL,
    cut_rule_version INTEGER NOT NULL
) STRICT;
INSERT INTO catalog_meta VALUES (1, 3, 'SRV_A', 'conversion-tool', 'test', '2026-10-06T00:00:00Z', 3);
PRAGMA user_version = 3;
'@
    Invoke-Sql -Db $v3 -Sql $sql
    $v3Check = Test-CatalogFile -Sqlite3 $sqlite3 -Db $v3
    Assert-That 'future schema version 3 remains fail-closed' (@($v3Check.Problems | Where-Object { $_ -like '*not a supported schema version*' }).Count -eq 1)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('Seal schema v2 tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
exit 0
