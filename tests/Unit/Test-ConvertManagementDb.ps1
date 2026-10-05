#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for tools/Convert-ManagementDb.ps1 (new-machine mode).

.DESCRIPTION
    Uses a small synthetic ManagementSync.sql (same statement format as the real one) and
    the sqlite3 executable named by the SQLITE3_PATH environment variable (CI downloads
    the pinned 3.53.4 and verifies its SHA-256). No network, no SQL Server.
    Marker values stand in for secrets. Exits with code 1 on failure, 2 when sqlite3 is missing.
    The SQL Server path (-SqlInstance) is not covered here: it needs a real server [V].
#>
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

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1')).Path
. $toolPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$script:Failures = 0
$script:Passed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}
function Invoke-Query {
    param([string]$Db, [string]$Sql)
    return (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Db, $Sql)).Trim()
}

# --- fixture ---------------------------------------------------------------
$markerA = 'Zq8Lm2' + 'MARKERA' + '41'
$markerB = 'Rt5Vb9' + 'MARKERB' + '63'
$markerC = 'Hy7Nc3' + 'MARKERC' + '85'
$eAcute = [string][char]0x00E9
$nl = "`r`n"

function New-TableDdl {
    param([string]$Schema, [string]$Table, [string[]]$Lines)
    return "IF OBJECT_ID('$Schema.$Table') IS NULL${nl}BEGIN${nl}    EXEC('CREATE TABLE [$Schema].[$Table] (${nl}" + ($Lines -join ",$nl") + "${nl})');${nl}END;${nl}${nl}"
}

$ddl = ''
$ddl += New-TableDdl 'cfg' 'ConfigRule' @(
    '    [RuleID] int IDENTITY(1,1) NOT NULL', '    [RuleCode] varchar(150) NOT NULL', '    [CountryCode] char(2) NULL',
    '    [ExpectedTemplate] nvarchar(4000) NOT NULL', '    [IsSensitive] bit NOT NULL', '    [ModifiedAt] datetime2 NOT NULL',
    '    CONSTRAINT [PK_ConfigRule_sync] PRIMARY KEY ([RuleID])')
$ddl += New-TableDdl 'cfg' 'LinksPageAsset' @(
    '    [AssetCode] varchar(60) NOT NULL', '    [Content] varbinary(max) NOT NULL', '    [ContentSha256] char(64) NOT NULL',
    '    CONSTRAINT [PK_LinksPageAsset_sync] PRIMARY KEY ([AssetCode])')
$ddl += New-TableDdl 'ops' 'Engine' @(
    '    [EngineCode] varchar(60) NOT NULL', '    [ScriptText] nvarchar(max) NOT NULL', '    [ScriptSha256] char(64) NOT NULL',
    '    [EngineVersion] varchar(40) NOT NULL', '    CONSTRAINT [PK_Engine_sync] PRIMARY KEY ([EngineCode])')
$ddl += New-TableDdl 'dbo' 'ManagedServer' @(
    '    [ServerCode] varchar(30) NOT NULL', '    [MachineName] sysname NOT NULL', '    [ServicesRoot] nvarchar(1000) NOT NULL',
    '    [IsEnabled] bit NOT NULL', '    [CreatedAt] datetime2 NOT NULL', '    [ModifiedAt] datetime2 NOT NULL',
    '    [ConfigBackupRoot] nvarchar(1000) NOT NULL', '    [ManagementDatabaseName] sysname NOT NULL',
    '    CONSTRAINT [PK_ManagedServer_sync] PRIMARY KEY ([ServerCode])')
$ddl += New-TableDdl 'dbo' 'ManagedInstance' @(
    '    [InstanceCode] varchar(20) NOT NULL', '    [ServerCode] varchar(30) NOT NULL', '    [IisIdentityPassword] nvarchar(255) NULL',
    '    [WebAccessPassword] nvarchar(255) NULL', '    [MobileAppToken] nvarchar(255) NULL', '    [Notes] nvarchar(1000) NULL',
    '    CONSTRAINT [PK_ManagedInstance_sync] PRIMARY KEY ([InstanceCode])')
$ddl += New-TableDdl 'cfg' 'IisServerPolicy' @(
    '    [ServerCode] varchar(30) NOT NULL', '    [ReconcileMode] varchar(30) NOT NULL', '    CONSTRAINT [PK_IisServerPolicy_sync] PRIMARY KEY ([ServerCode])')
$ddl += New-TableDdl 'ui' 'Resource' @(
    '    [ResourceCode] varchar(100) NOT NULL', '    [CultureCode] varchar(10) NOT NULL', '    [ResourceValue] nvarchar(max) NOT NULL',
    '    [RowVersion] timestamp NOT NULL', '    CONSTRAINT [PK_Resource_sync] PRIMARY KEY ([ResourceCode], [CultureCode])')
$ddl += New-TableDdl 'app' 'Job' @('    [JobID] int NOT NULL', '    [ResultMessage] nvarchar(max) NULL', '    CONSTRAINT [PK_Job_sync] PRIMARY KEY ([JobID])')

function New-Insert {
    param([string]$Schema, [string]$Table, [string[]]$Columns, [string]$Values)
    return ('INSERT INTO [{0}].[{1}] ({2}) VALUES ({3});' -f $Schema, $Table, (($Columns | ForEach-Object { "[$_]" }) -join ', '), $Values) + $nl
}
function Get-Sha256Of { param([byte[]]$b) $s = [Security.Cryptography.SHA256]::Create(); try { return ([BitConverter]::ToString($s.ComputeHash($b)) -replace '-', '') } finally { $s.Dispose() } }

$blob = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF)
$blobHex = '0x' + [Convert]::ToHexString($blob)
$blobSha = Get-Sha256Of $blob
$cr = @('RuleID', 'RuleCode', 'CountryCode', 'ExpectedTemplate', 'IsSensitive', 'ModifiedAt')
$data = ''
$data += 'SET IDENTITY_INSERT [cfg].[ConfigRule] ON;' + $nl
$data += New-Insert 'cfg' 'ConfigRule' $cr "10, N'PLAIN_RULE', N'PT', N'plain text value', 0, '2026-01-02 03:04:05.1234567'"
$data += New-Insert 'cfg' 'ConfigRule' $cr "11, N'APP_CLIENT_SECRET', NULL, N'$markerA', 1, '2026-01-02 03:04:05.0000000'"
$data += New-Insert 'cfg' 'ConfigRule' $cr "12, N'KC_BOOTSTRAP_PASSWORD', NULL, N'bootstrap-admin-password=$markerB', 1, '2026-01-02 03:04:05.0000000'"
$data += New-Insert 'cfg' 'ConfigRule' $cr "13, N'CONN_WITH_PLACEHOLDER', N'ES', N'Server={ServerName};Integrated Security=SSPI;', 1, '2026-01-02 03:04:05.0000000'"
$data += 'SET IDENTITY_INSERT [cfg].[ConfigRule] OFF;' + $nl
$data += New-Insert 'cfg' 'LinksPageAsset' @('AssetCode', 'Content', 'ContentSha256') "N'LOGO', $blobHex, N'$blobSha'"
$data += New-Insert 'ops' 'Engine' @('EngineCode', 'ScriptText', 'ScriptSha256', 'EngineVersion') "N'E1', N'engine text that must not be carried', N'$('0' * 64)', N'1.0'"
$data += New-Insert 'dbo' 'ManagedServer' @('ServerCode', 'MachineName', 'ServicesRoot', 'IsEnabled', 'CreatedAt', 'ModifiedAt', 'ConfigBackupRoot', 'ManagementDatabaseName') "N'OLD_SRV', N'OLD-HOST', N'D:\Services', 1, '2026-01-01 00:00:00.0000000', '2026-01-01 00:00:00.0000000', N'D:\Backups', N'_mgmt'"
$data += New-Insert 'dbo' 'ManagedInstance' @('InstanceCode', 'ServerCode', 'IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken', 'Notes') "N'INST1', N'OLD_SRV', N'$markerC', N'$markerC', N'$markerC', NULL"
$data += New-Insert 'cfg' 'IisServerPolicy' @('ServerCode', 'ReconcileMode') "N'OLD_SRV', N'CREATE_AND_CORRECT'"
$data += New-Insert 'ui' 'Resource' @('ResourceCode', 'CultureCode', 'ResourceValue') "N'HELLO', N'pt-PT', N'Ol${eAcute} it''s fine'"
$multi = 'line1' + "`r`n" + 'line2' + "`n" + 'line3' + "`r" + 'line4' + "`t" + 'tab ' + $eAcute + " 'q' " + "`r`n" + 'end' + "`r`n"
$data += New-Insert 'ui' 'Resource' @('ResourceCode', 'CultureCode', 'ResourceValue') ("N'MULTI', N'xx-XX', N'" + $multi.Replace("'", "''") + "'")
# A history table with a statement that looks like another INSERT inside a string (must be skipped, not parsed).
$data += New-Insert 'app' 'Job' @('JobID', 'ResultMessage') "1, N'line one${nl}INSERT INTO [cfg].[ConfigRule] ([RuleCode]) VALUES (N''TRAP'');${nl}end'"
$fixture = '/* header */' + $nl + $ddl + $data

$tables = [ordered]@{
    'cfg.ConfigRule' = 'G'; 'cfg.LinksPageAsset' = 'G'; 'ops.Engine' = 'G'; 'ui.Resource' = 'G'
    'dbo.ManagedServer' = 'S'; 'cfg.IisServerPolicy' = 'S'; 'dbo.ManagedInstance' = 'I'
}
$script:CarriedTables = $tables

function New-Source {
    param([string]$Text)
    $schema = Read-SyncSchema -Text $Text -Tables @($script:CarriedTables.Keys)
    $rows = Read-SyncRows -Text $Text -Schema $schema
    return [pscustomobject]@{ Schema = $schema; Rows = $rows }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('convert-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 1. Reading the source ----------------------------------------------------
    $source = New-Source -Text $fixture
    Assert-That 'schema: columns, identity and composite key are read' (($source.Schema['cfg.ConfigRule'].Columns | Where-Object Name -eq 'RuleID').Identity -and $source.Schema['ui.Resource'].PrimaryKey.Count -eq 2)
    Assert-That 'rows: only the whitelisted tables are read' ($source.Rows['cfg.ConfigRule'].Count -eq 4 -and $source.Rows['dbo.ManagedServer'].Count -eq 1)
    Assert-That 'rows: a string that looks like an INSERT is skipped, not parsed' (-not ($source.Rows['cfg.ConfigRule'] | Where-Object { $_['RuleCode'] -eq 'TRAP' }))
    Assert-That 'rows: bit, long and bytes get native types' ($source.Rows['cfg.ConfigRule'][1]['IsSensitive'] -eq 1 -and $source.Rows['cfg.ConfigRule'][0]['IsSensitive'] -eq 0 -and $source.Rows['cfg.ConfigRule'][0]['RuleID'] -is [long] -and $source.Rows['cfg.LinksPageAsset'][0]['Content'] -is [byte[]])
    Assert-That 'rows: quotes and non-ASCII text are unescaped' ($source.Rows['ui.Resource'][0]['ResourceValue'] -eq ('Ol' + $eAcute + " it's fine"))

    # 2. Conversion --------------------------------------------------------------
    $out = Join-Path $work 'out'
    $info = @{ kind = 'test' }
    $r = Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder $out -Sqlite3 $sqlite3 -Code 'NEW_SRV' -Machine 'NEW-HOST' -Services 'C:\Services' -BackupRoot 'C:\Backups' -SourceRef 'unit test'
    $db = $r.Catalog
    Assert-That 'catalog and manifest are written, no temp files left' ((Test-Path $db) -and (Test-Path $r.Manifest) -and -not (Get-ChildItem $out -Filter '*.tmp') -and -not (Get-ChildItem $out -Filter '*.build.sql'))
    Assert-That 'integrity check and user_version' ((Invoke-Query $db 'PRAGMA integrity_check;') -eq 'ok' -and (Invoke-Query $db 'PRAGMA user_version;') -eq '1')
    Assert-That 'catalog_meta has the one expected row' ((Invoke-Query $db 'SELECT schema_version, server_code, source_kind, source_reference, cut_rule_version FROM catalog_meta;') -eq '1|NEW_SRV|conversion-tool|unit test|1')
    Assert-That 'all tables are STRICT' ((Invoke-Query $db "SELECT count(*) FROM pragma_table_list WHERE schema='main' AND strict=0 AND name NOT LIKE 'sqlite_%';") -eq '0')

    # 3. What does and does not enter ---------------------------------------------
    Assert-That 'global rows are copied (4 rules, 1 asset, 1 engine, 2 resources)' ((Invoke-Query $db 'SELECT (SELECT count(*) FROM cfg_ConfigRule), (SELECT count(*) FROM cfg_LinksPageAsset), (SELECT count(*) FROM ops_Engine), (SELECT count(*) FROM ui_Resource);') -eq '4|1|1|2')
    Assert-That 'cut tables are empty; only the new ManagedServer row exists' ((Invoke-Query $db 'SELECT (SELECT count(*) FROM dbo_ManagedInstance), (SELECT count(*) FROM cfg_IisServerPolicy), (SELECT count(*) FROM dbo_ManagedServer), (SELECT ServerCode || MachineName FROM dbo_ManagedServer);') -eq '0|0|1|NEW_SRVNEW-HOST')
    Assert-That 'the old server row of the source is not copied' ((Invoke-Query $db "SELECT count(*) FROM dbo_ManagedServer WHERE ServerCode = 'OLD_SRV';") -eq '0')
    $columns = Invoke-Query $db "SELECT group_concat(m.name || '.' || p.name) FROM sqlite_master m, pragma_table_info(m.name) p WHERE m.type='table';"
    Assert-That 'secret, script, rowversion and ManagementDatabaseName columns do not exist' (($columns -notmatch 'IisIdentityPassword|WebAccessPassword|MobileAppToken|ScriptText|ScriptSha256|RowVersion|ManagementDatabaseName'))
    Assert-That 'the history trap row never appears' ((Invoke-Query $db "SELECT count(*) FROM cfg_ConfigRule WHERE RuleCode = 'TRAP';") -eq '0')

    # 4. Redaction and secret safety ------------------------------------------------
    $bytes = [System.IO.File]::ReadAllBytes($db)
    $dbText = [System.Text.Encoding]::Latin1.GetString($bytes)
    $manifestText = [System.IO.File]::ReadAllText($r.Manifest)
    foreach ($m in @($markerA, $markerB, $markerC)) {
        Assert-That ('marker value is not in the catalog file: ' + $m.Substring(6, 7)) (-not $dbText.Contains($m))
        Assert-That ('marker value is not in the manifest: ' + $m.Substring(6, 7)) (-not $manifestText.Contains($m))
    }
    Assert-That 'a whole-value secret becomes a reference token' ((Invoke-Query $db "SELECT ExpectedTemplate FROM cfg_ConfigRule WHERE RuleCode = 'APP_CLIENT_SECRET';") -eq '{{secret:RULE:APP_CLIENT_SECRET}}')
    Assert-That 'a label=value secret keeps its label' ((Invoke-Query $db "SELECT ExpectedTemplate FROM cfg_ConfigRule WHERE RuleCode = 'KC_BOOTSTRAP_PASSWORD';") -eq 'bootstrap-admin-password={{secret:RULE:KC_BOOTSTRAP_PASSWORD}}')
    Assert-That 'placeholder and non-sensitive templates are unchanged' ((Invoke-Query $db "SELECT group_concat(ExpectedTemplate, ' / ') FROM cfg_ConfigRule WHERE RuleCode IN ('PLAIN_RULE','CONN_WITH_PLACEHOLDER');") -eq 'plain text value / Server={ServerName};Integrated Security=SSPI;')
    Assert-That 'redaction is reported by rule code, count 2' ($r.Redacted -eq 2)
    $leak = New-Source -Text $fixture.Replace("N'Ol$eAcute it''s fine'", "N'Password = $markerC'")
    Assert-Throws 'a secret-like literal outside the rule tables stops the run' { Invoke-NewMachineConversion -Source $leak -SourceInfo $info -Folder (Join-Path $work 'leak') -Sqlite3 $sqlite3 -Code 'X1' -Machine 'H' -Services 'S' -BackupRoot 'B' } '*Safety net*'
    Assert-That 'nothing is written when the safety net stops the run' (-not (Test-Path (Join-Path $work 'leak' 'catalog-X1.db')))

    # 4b. Text is byte-exact (owner: nothing about case or line endings may change) ------------
    $expectedHex = [Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes($multi))
    Assert-That 'multi-line text keeps CRLF, lone LF, lone CR and tab byte for byte' ((Invoke-Query $db "SELECT hex(ResourceValue) FROM ui_Resource WHERE ResourceCode = 'MULTI';") -eq $expectedHex)
    Assert-That 'the stored multi-line value is still TEXT' ((Invoke-Query $db "SELECT typeof(ResourceValue) FROM ui_Resource WHERE ResourceCode = 'MULTI';") -eq 'text')
    Assert-That 'a normal value with quotes is stored without hex casting and unchanged' ((Invoke-Query $db "SELECT ResourceValue FROM ui_Resource WHERE ResourceCode = 'HELLO';") -eq ('Ol' + $eAcute + " it's fine"))
    Assert-That 'text case is never changed (mixed-case code stored as given)' ((Invoke-Query $db "SELECT ServerCode FROM dbo_ManagedServer;") -ceq 'NEW_SRV')

    # 5. Types and constraints -------------------------------------------------------
    Assert-That 'datetime2 keeps its value, with T and no zone' ((Invoke-Query $db "SELECT ModifiedAt FROM cfg_ConfigRule WHERE RuleID = 10;") -eq '2026-01-02T03:04:05.1234567')
    Assert-That 'identity value is kept; bit is 0 or 1; char column holds text' ((Invoke-Query $db "SELECT RuleID || '|' || IsSensitive || '|' || CountryCode FROM cfg_ConfigRule WHERE RuleID = 10;") -eq '10|0|PT')
    Assert-That 'BLOB is a real blob that hashes to its stored SHA-256' ((Invoke-Query $db "SELECT typeof(Content) || '|' || upper(hex(Content)) FROM cfg_LinksPageAsset;") -eq ('blob|' + [Convert]::ToHexString($blob)))
    Assert-That 'non-ASCII text is stored as UTF-8' ((Invoke-Query $db "SELECT hex(ResourceValue) FROM ui_Resource;") -match 'C3A9')
    Assert-That 'by default code columns compare exactly (no folding)' ((Invoke-Query $db "SELECT count(*) FROM dbo_ManagedServer WHERE ServerCode = 'new_srv';") -eq '0')
    Assert-That 'a bit CHECK rejects other values' ((Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($db, "SELECT sql FROM sqlite_master WHERE name = 'cfg_ConfigRule';")) -match 'CHECK \("IsSensitive" IN \(0, 1\)\)')
    $r2 = Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder (Join-Path $work 'nocase') -Sqlite3 $sqlite3 -Code 'NEW_SRV' -Machine 'NEW-HOST' -Services 'C:\Services' -BackupRoot 'C:\Backups' -SourceRef 'x' -UseCodeCollation $true
    Assert-That 'with -CodeCollation NoCase the same lookup folds ASCII case' ((Invoke-Query $r2.Catalog "SELECT count(*) FROM dbo_ManagedServer WHERE ServerCode = 'new_srv';") -eq '1')
    Assert-That 'with NoCase the stored text is still exactly as given' ((Invoke-Query $r2.Catalog "SELECT ServerCode FROM dbo_ManagedServer;") -ceq 'NEW_SRV')

    # 6. Manifest ----------------------------------------------------------------------
    $manifestRaw = [System.IO.File]::ReadAllBytes($r.Manifest)
    Assert-That 'manifest is ASCII and LF' (-not ($manifestRaw | Where-Object { $_ -gt 127 -or $_ -eq 13 }))
    $manifest = [System.Text.Encoding]::UTF8.GetString($manifestRaw) | ConvertFrom-Json
    $entry = $manifest.catalogs[0]
    Assert-That 'manifest SHA-256 and size match the file' ($entry.sha256 -eq (Get-FileHash $db -Algorithm SHA256).Hash.ToLowerInvariant() -and $entry.bytes -eq (Get-Item $db).Length)
    Assert-That 'manifest lists redacted rule codes, empty-policy findings and excluded columns' ($entry.redactedRuleCount -eq 2 -and $entry.redactedRules.Count -eq 2 -and @($entry.findings | Where-Object { $_ -like '*cfg_IisServerPolicy is empty*' }).Count -eq 1 -and $entry.excludedColumns -contains 'dbo.ManagedInstance.IisIdentityPassword')
    Assert-That 'manifest row counts match' (@($entry.tables | Where-Object { $_.sourceRows -ne $_.destinationRows }).Count -eq 0)

    # 7. Input checks --------------------------------------------------------------------
    # 8. Collation finding ---------------------------------------------------------------
    Assert-That 'no collation finding when every code is ASCII' (@($entry.findings | Where-Object { $_ -like '*non-ASCII*' }).Count -eq 0)
    $accent = New-Source -Text $fixture.Replace("N'PLAIN_RULE'", "N'PLAIN_R${eAcute}GLE'")
    $r3 = Invoke-NewMachineConversion -Source $accent -SourceInfo $info -Folder (Join-Path $work 'accent') -Sqlite3 $sqlite3 -Code 'NEW_SRV' -Machine 'NEW-HOST' -Services 'C:\Services' -BackupRoot 'C:\Backups' -SourceRef 'x' -UseCodeCollation $true
    $m3 = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($r3.Manifest)) | ConvertFrom-Json).catalogs[0]
    Assert-That 'a non-ASCII code value is reported as a finding (count only, no value)' (@($m3.findings | Where-Object { $_ -like 'cfg_ConfigRule.RuleCode: 1 value(s) contain non-ASCII*' }).Count -eq 1 -and -not ($m3 | ConvertTo-Json -Depth 8).Contains('PLAIN_R'))

    Assert-Throws 'an existing ServerCode is refused (cut mode is B3)' { Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder (Join-Path $work 'o1') -Sqlite3 $sqlite3 -Code 'old_srv' -Machine 'H' -Services 'S' -BackupRoot 'B' } '*already exists*'
    Assert-Throws 'an invalid ServerCode is refused' { Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder (Join-Path $work 'o2') -Sqlite3 $sqlite3 -Code 'bad code!' -Machine 'H' -Services 'S' -BackupRoot 'B' } '*ServerCode must be*'
    Assert-Throws 'a missing sqlite3 is refused' { Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder (Join-Path $work 'o3') -Sqlite3 (Join-Path $work 'nope.exe') -Code 'Z1' -Machine 'H' -Services 'S' -BackupRoot 'B' } '*sqlite3 was not found*'
    $noTable = $fixture.Replace('CREATE TABLE [cfg].[IisServerPolicy] (', 'CREATE TABLE [cfg].[Other] (')
    Assert-Throws 'a whitelisted table missing from the source is an error' { New-Source -Text $noTable } '*was not found in the source schema*'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
