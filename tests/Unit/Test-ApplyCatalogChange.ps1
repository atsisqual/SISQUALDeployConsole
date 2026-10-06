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

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Apply-CatalogChange.ps1')).Path
. $toolPath -ProposalPath 'unused' -CatalogPath 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failed++; Write-Host ('FAIL  {0} {1}' -f $Name, $Detail) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false; $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and $message -like $Like) $message
}
function Invoke-Query {
    param([string]$Db, [string]$Sql)
    return (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $Db, $Sql)).Trim()
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('c9-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

function New-TestCatalog {
    param([string]$Name)
    $db = Join-Path $work ($Name + '.db')
    $sql = @'
PRAGMA foreign_keys = ON;
PRAGMA user_version = 1;
CREATE TABLE catalog_meta (
  meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),
  schema_version INTEGER NOT NULL,
  server_code TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_reference TEXT NOT NULL,
  built_at_utc TEXT NOT NULL,
  cut_rule_version INTEGER NOT NULL
) STRICT;
INSERT INTO catalog_meta VALUES (1,1,'SRV_A','conversion-tool','c9-test','2026-01-01T00:00:00Z',1);
CREATE TABLE cfg_LinksPageInstanceApplication (
  InstanceCode TEXT NOT NULL,
  ApplicationCode TEXT NOT NULL,
  IsVisibleInWeb INTEGER NOT NULL CHECK (IsVisibleInWeb IN (0,1)),
  ModifiedAt TEXT NULL,
  PRIMARY KEY (InstanceCode, ApplicationCode)
) STRICT;
INSERT INTO cfg_LinksPageInstanceApplication VALUES ('INST1','APP1',1,'2026-01-01T00:00:00');
INSERT INTO cfg_LinksPageInstanceApplication VALUES ('INST1','APP2',0,NULL);
CREATE TABLE cfg_ConfigRule (
  RuleCode TEXT PRIMARY KEY,
  ExpectedTemplate TEXT NOT NULL
) STRICT;
INSERT INTO cfg_ConfigRule VALUES ('SAFE_RULE','safe text');
CREATE TABLE cfg_Text (
  Code TEXT PRIMARY KEY,
  Value TEXT NOT NULL
) STRICT;
INSERT INTO cfg_Text VALUES ('T1','original');
CREATE TABLE cfg_Parent (
  Id INTEGER PRIMARY KEY,
  Name TEXT NOT NULL
) STRICT;
INSERT INTO cfg_Parent VALUES (1,'parent');
CREATE TABLE cfg_Child (
  Id INTEGER PRIMARY KEY,
  ParentId INTEGER NOT NULL REFERENCES cfg_Parent(Id),
  Name TEXT NOT NULL
) STRICT;
INSERT INTO cfg_Child VALUES (10,1,'child');
CREATE TABLE cfg_Data (
  Code TEXT PRIMARY KEY,
  Payload BLOB NULL,
  Amount REAL NULL
) STRICT;
INSERT INTO cfg_Data VALUES ('D1',X'0102',1.5);
CREATE TABLE cfg_LinksPageDirectory (
  InstanceCode TEXT PRIMARY KEY,
  ServerCode TEXT NOT NULL
) STRICT;
'@
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($db, $sql))
    return $db
}

function Write-Proposal {
    param(
        [string]$Db,
        [string]$Name,
        [object[]]$Operations,
        [string]$Hash = '',
        [string]$Server = 'SRV_A',
        [string]$Note = 'unit test'
    )
    if (-not $Hash) { $Hash = Get-C9Sha256 -Path $Db }
    $proposal = [ordered]@{
        contractVersion = '0.1-proposed'
        changeId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
        catalogServerCode = $Server
        baseCatalogSha256 = $Hash
        note = $Note
        operations = @($Operations)
    }
    $path = Join-Path $work ($Name + '.json')
    $json = ($proposal | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
    return $path
}

try {
    # 1. Dry-run validates but writes nothing.
    $db = New-TestCatalog 'dry'
    $before = Get-C9Sha256 -Path $db
    $proposal = Write-Proposal -Db $db -Name 'dry' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1'; ApplicationCode='APP1' }; expected=[ordered]@{ IsVisibleInWeb=1 }; values=[ordered]@{ IsVisibleInWeb=0 } }
    )
    $baseline = Join-Path $work 'dry-baseline.db'
    $r = Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $baseline -Preview $true -Confirmed $true 6>$null
    Assert-That 'dry-run reports not applied' (-not $r.Applied -and -not $r.RequiresReseal)
    Assert-That 'dry-run leaves catalog byte-exact and writes no baseline' ((Get-C9Sha256 $db) -ceq $before -and -not (Test-Path $baseline))

    # 2. One atomic proposal can update, insert and delete by the real composite PK.
    $db = New-TestCatalog 'apply'
    $before = Get-C9Sha256 -Path $db
    $proposal = Write-Proposal -Db $db -Name 'apply' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1'; ApplicationCode='APP1' }; expected=[ordered]@{ IsVisibleInWeb=1 }; values=[ordered]@{ IsVisibleInWeb=0 } },
        [ordered]@{ kind='INSERT'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST2'; ApplicationCode='APP1' }; values=[ordered]@{ IsVisibleInWeb=1; ModifiedAt=$null } },
        [ordered]@{ kind='DELETE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1'; ApplicationCode='APP2' }; expected=[ordered]@{ IsVisibleInWeb=0 } }
    )
    $baseline = Join-Path $work 'apply-baseline.db'
    $r = Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $baseline -Preview $false -Confirmed $true 6>$null
    Assert-That 'apply reports changed catalog and reseal required' ($r.Applied -and $r.RequiresReseal -and $r.Operations -eq 3)
    Assert-That 'baseline is byte-exact pre-edit catalog' ((Get-C9Sha256 $baseline) -ceq $before)
    Assert-That 'update/insert/delete were applied exactly' ((Invoke-Query $db "SELECT (SELECT IsVisibleInWeb FROM cfg_LinksPageInstanceApplication WHERE InstanceCode='INST1' AND ApplicationCode='APP1') || '|' || (SELECT count(*) FROM cfg_LinksPageInstanceApplication WHERE InstanceCode='INST2' AND ApplicationCode='APP1' AND IsVisibleInWeb=1) || '|' || (SELECT count(*) FROM cfg_LinksPageInstanceApplication WHERE InstanceCode='INST1' AND ApplicationCode='APP2');") -ceq '0|1|0')
    Assert-That 'successful edit keeps catalog structurally safe' ((Test-CatalogFile -Sqlite3 $sqlite3 -Db $db -ExpectedServerCode 'SRV_A').Problems.Count -eq 0)

    # 3. Text that looks like SQL stays byte-exact data and is never executed.
    $db = New-TestCatalog 'text'
    $payload = "x'); DROP TABLE cfg_Parent; --"
    $proposal = Write-Proposal -Db $db -Name 'text' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Text'; key=[ordered]@{ Code='T1' }; expected=[ordered]@{ Value='original' }; values=[ordered]@{ Value=$payload } }
    )
    $baseline = Join-Path $work 'text-baseline.db'
    [void](Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $baseline -Confirmed $true 6>$null)
    $storedHex = Invoke-Query $db "SELECT hex(Value) FROM cfg_Text WHERE Code='T1';"
    $expectedHex = [Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes($payload))
    Assert-That 'SQL-shaped text is stored byte-exact as data' ($storedHex -ceq $expectedHex)
    Assert-That 'SQL-shaped text cannot execute' ((Invoke-Query $db 'SELECT count(*) FROM cfg_Parent;') -ceq '1')

    # 4. Stale/wrong-target proposals fail before a write.
    $db = New-TestCatalog 'stale'
    $before = Get-C9Sha256 $db
    $proposal = Write-Proposal -Db $db -Name 'stale' -Hash ('0' * 64) -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Text'; key=[ordered]@{ Code='T1' }; expected=[ordered]@{ Value='original' }; values=[ordered]@{ Value='new' } }
    )
    Assert-Throws 'stale base hash is refused' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'stale-base.db') -Confirmed $true 6>$null } '*stale*'
    Assert-That 'stale proposal leaves original unchanged' ((Get-C9Sha256 $db) -ceq $before)
    $proposal = Write-Proposal -Db $db -Name 'server' -Server 'srv_a' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Text'; key=[ordered]@{ Code='T1' }; expected=[ordered]@{ Value='original' }; values=[ordered]@{ Value='new' } }
    )
    Assert-Throws 'server code comparison is exact' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'server-base.db') -Confirmed $true 6>$null } '*does not match*'

    # 5. Primary-key and optimistic-state rules fail closed.
    $db = New-TestCatalog 'state'
    $before = Get-C9Sha256 $db
    $proposal = Write-Proposal -Db $db -Name 'wrong-key' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1' }; expected=[ordered]@{ IsVisibleInWeb=1 }; values=[ordered]@{ IsVisibleInWeb=0 } }
    )
    Assert-Throws 'key must be the exact live composite primary key' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'wrong-key-base.db') -Confirmed $true 6>$null } '*primary-key*'
    $proposal = Write-Proposal -Db $db -Name 'wrong-expected' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1'; ApplicationCode='APP1' }; expected=[ordered]@{ IsVisibleInWeb=0 }; values=[ordered]@{ IsVisibleInWeb=1 } }
    )
    $badBaseline = Join-Path $work 'wrong-expected-base.db'
    Assert-Throws 'expected-value mismatch affects zero rows and is refused' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $badBaseline -Confirmed $true 6>$null } '*exactly one row*'
    Assert-That 'failed expected-value check leaves original and no baseline' ((Get-C9Sha256 $db) -ceq $before -and -not (Test-Path $badBaseline))
    $proposal = Write-Proposal -Db $db -Name 'noop' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Text'; key=[ordered]@{ Code='T1' }; expected=[ordered]@{ Value='original' }; values=[ordered]@{ Value='original' } }
    )
    Assert-Throws 'no-op update is refused' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'noop-base.db') -Confirmed $true 6>$null } '*no-op*'

    # 6. Safety boundaries: meta/derived/BLOB and type mismatch.
    $db = New-TestCatalog 'bounds'
    $proposal = Write-Proposal -Db $db -Name 'meta' -Operations @(
        [ordered]@{ kind='UPDATE'; table='catalog_meta'; key=[ordered]@{ meta_id=1 }; expected=[ordered]@{ source_reference='c9-test' }; values=[ordered]@{ source_reference='changed' } }
    )
    Assert-Throws 'catalog_meta is not editable by C9' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'meta-base.db') -Confirmed $true 6>$null } '*not editable*'
    $proposal = Write-Proposal -Db $db -Name 'derived' -Operations @(
        [ordered]@{ kind='INSERT'; table='cfg_LinksPageDirectory'; key=[ordered]@{ InstanceCode='REMOTE1' }; values=[ordered]@{ ServerCode='SRV_B' } }
    )
    Assert-Throws 'derived cross-machine directory cannot be hand-edited' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'derived-base.db') -Confirmed $true 6>$null } '*not editable*'
    $proposal = Write-Proposal -Db $db -Name 'blob' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Data'; key=[ordered]@{ Code='D1' }; expected=[ordered]@{ Payload=$null }; values=[ordered]@{ Payload='0102' } }
    )
    Assert-Throws 'BLOB edits are refused in C9 V1' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'blob-base.db') -Confirmed $true 6>$null } '*BLOB affinity*'
    $proposal = Write-Proposal -Db $db -Name 'type' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_LinksPageInstanceApplication'; key=[ordered]@{ InstanceCode='INST1'; ApplicationCode='APP1' }; expected=[ordered]@{ IsVisibleInWeb=1 }; values=[ordered]@{ IsVisibleInWeb='0' } }
    )
    Assert-Throws 'SQLite INTEGER column refuses JSON string values' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'type-base.db') -Confirmed $true 6>$null } '*requires a JSON integer*'

    # 7. Foreign-key and secret scan validation happen on the staged copy only.
    $db = New-TestCatalog 'fk'
    $before = Get-C9Sha256 $db
    $proposal = Write-Proposal -Db $db -Name 'fk' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Child'; key=[ordered]@{ Id=10 }; expected=[ordered]@{ ParentId=1 }; values=[ordered]@{ ParentId=999 } }
    )
    $badBaseline = Join-Path $work 'fk-base.db'
    Assert-Throws 'foreign-key violation cannot replace original' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $badBaseline -Confirmed $true 6>$null } '*rejected*'
    Assert-That 'FK failure leaves original and no baseline' ((Get-C9Sha256 $db) -ceq $before -and -not (Test-Path $badBaseline))

    $db = New-TestCatalog 'secret'
    $before = Get-C9Sha256 $db
    $proposal = Write-Proposal -Db $db -Name 'secret' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_ConfigRule'; key=[ordered]@{ RuleCode='SAFE_RULE' }; expected=[ordered]@{ ExpectedTemplate='safe text' }; values=[ordered]@{ ExpectedTemplate='password=abcdefghi' } }
    )
    $badBaseline = Join-Path $work 'secret-base.db'
    Assert-Throws 'existing seal secret scanner blocks a secret-like edit' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline $badBaseline -Confirmed $true 6>$null } '*staged catalog is not safe*'
    Assert-That 'secret-scan failure leaves original and no baseline' ((Get-C9Sha256 $db) -ceq $before -and -not (Test-Path $badBaseline))

    # 8. JSON itself is strict and reviewable.
    $db = New-TestCatalog 'json'
    $path = Join-Path $work 'duplicate.json'
    $hash = Get-C9Sha256 $db
    $json = '{"contractVersion":"0.1-proposed","changeId":"00000000-0000-4000-8000-000000000001","catalogServerCode":"SRV_A","baseCatalogSha256":"' + $hash + '","note":"a","note":"b","operations":[]}'
    [System.IO.File]::WriteAllText($path, $json, [System.Text.UTF8Encoding]::new($false))
    Assert-Throws 'duplicate JSON member is refused' { Invoke-CatalogChange -Proposal $path -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'dup-base.db') -Confirmed $true 6>$null } '*duplicate property*'

    $proposal = Write-Proposal -Db $db -Name 'float' -Operations @(
        [ordered]@{ kind='UPDATE'; table='cfg_Parent'; key=[ordered]@{ Id=1 }; expected=[ordered]@{ Name='parent' }; values=[ordered]@{ Name='next' } }
    )
    $raw = [System.IO.File]::ReadAllText($proposal).Replace('"Id": 1', '"Id": 1.5')
    [System.IO.File]::WriteAllText($proposal, $raw, [System.Text.UTF8Encoding]::new($false))
    Assert-Throws 'floating-point JSON numbers are refused' { Invoke-CatalogChange -Proposal $proposal -Catalog $db -Sqlite3 $sqlite3 -Baseline (Join-Path $work 'float-base.db') -Confirmed $true 6>$null } '*must be integers*'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('C9 catalog-change tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
