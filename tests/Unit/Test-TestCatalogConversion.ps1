#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for tools/Test-CatalogConversion.ps1.

.DESCRIPTION
    A verification tool is only worth its failures. This test builds catalogs with the converter
    from a small synthetic source (cut mode and new-machine mode), requires the tool to pass on
    the intact catalogs, and then damages a copy of the catalogs in ten different ways, each of
    which the tool must report in the right group of checks. Marker values stand in for secrets.
    Needs SQLITE3_PATH (the pinned sqlite3). No network, no SQL Server.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite3 = $env:SQLITE3_PATH
if ([string]::IsNullOrWhiteSpace($sqlite3)) { $found = Get-Command sqlite3 -ErrorAction SilentlyContinue; if ($found) { $sqlite3 = $found.Source } }
if ([string]::IsNullOrWhiteSpace($sqlite3) -or -not (Test-Path -LiteralPath $sqlite3 -PathType Leaf)) {
    Write-Host 'sqlite3 was not found. Set SQLITE3_PATH to the pinned sqlite3 executable.'
    exit 2
}

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Test-CatalogConversion.ps1')).Path
. $toolPath -SyncFile 'unused' -CatalogFolder 'unused' -Sqlite3Path 'unused'

$script:Failures = 0
$script:Passed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}

$markerA = 'Zq8Lm2' + 'MARKERA' + '41'
$markerC = 'Hy7Nc3' + 'MARKERC' + '85'
$nl = "`r`n"
$eAcute = [string][char]0x00E9

function New-TableDdl {
    param([string]$Schema, [string]$Table, [string[]]$Lines)
    return "IF OBJECT_ID('$Schema.$Table') IS NULL${nl}BEGIN${nl}    EXEC('CREATE TABLE [$Schema].[$Table] (${nl}" + ($Lines -join ",$nl") + "${nl})');${nl}END;${nl}${nl}"
}
function New-Insert {
    param([string]$Schema, [string]$Table, [string[]]$Columns, [string]$Values)
    return ('INSERT INTO [{0}].[{1}] ({2}) VALUES ({3});' -f $Schema, $Table, (($Columns | ForEach-Object { "[$_]" }) -join ', '), $Values) + $nl
}

# --- synthetic source: 3 servers, 4 instances, a rule with a secret, a template with its stored hash ----------
$ddl = ''
$ddl += New-TableDdl 'cfg' 'ConfigRule' @('    [RuleID] int IDENTITY(1,1) NOT NULL', '    [RuleCode] varchar(150) NOT NULL', '    [ExpectedTemplate] nvarchar(4000) NOT NULL', '    [IsSensitive] bit NOT NULL', '    [ModifiedAt] datetime2 NOT NULL', '    CONSTRAINT [PK_ConfigRule_sync] PRIMARY KEY ([RuleID])')
$ddl += New-TableDdl 'cfg' 'LinksPageTemplate' @('    [TemplateCode] varchar(60) NOT NULL', '    [ContentTemplate] nvarchar(max) NOT NULL', '    [ContentSha256] char(64) NOT NULL', '    [IsEnabled] bit NOT NULL', '    CONSTRAINT [PK_LPT_sync] PRIMARY KEY ([TemplateCode])')
$ddl += New-TableDdl 'ops' 'Engine' @('    [EngineCode] varchar(60) NOT NULL', '    [ScriptText] nvarchar(max) NOT NULL', '    [ScriptSha256] char(64) NOT NULL', '    [EngineVersion] varchar(40) NOT NULL', '    CONSTRAINT [PK_Engine_sync] PRIMARY KEY ([EngineCode])')
$ddl += New-TableDdl 'dbo' 'ManagedServer' @('    [ServerCode] varchar(30) NOT NULL', '    [MachineName] sysname NOT NULL', '    [ServicesRoot] nvarchar(1000) NOT NULL', '    [IsEnabled] bit NOT NULL', '    [CreatedAt] datetime2 NOT NULL', '    [ModifiedAt] datetime2 NOT NULL', '    [ConfigBackupRoot] nvarchar(1000) NOT NULL', '    [ManagementDatabaseName] sysname NOT NULL', '    CONSTRAINT [PK_ManagedServer_sync] PRIMARY KEY ([ServerCode])')
$ddl += New-TableDdl 'dbo' 'ManagedInstance' @('    [InstanceCode] varchar(20) NOT NULL', '    [ServerCode] varchar(30) NOT NULL', '    [IisIdentityPassword] nvarchar(255) NULL', '    [WebAccessPassword] nvarchar(255) NULL', '    [MobileAppToken] nvarchar(255) NULL', '    [Notes] nvarchar(1000) NULL', '    CONSTRAINT [PK_ManagedInstance_sync] PRIMARY KEY ([InstanceCode])')
$ddl += New-TableDdl 'cfg' 'IisServerPolicy' @('    [ServerCode] varchar(30) NOT NULL', '    [ReconcileMode] varchar(30) NOT NULL', '    CONSTRAINT [PK_IisServerPolicy_sync] PRIMARY KEY ([ServerCode])')
$ddl += New-TableDdl 'cfg' 'LinksProfileInstance' @('    [ProfileCode] varchar(30) NOT NULL', '    [InstanceCode] varchar(20) NOT NULL', '    [ModifiedAt] datetime2 NOT NULL', '    CONSTRAINT [PK_LPI_sync] PRIMARY KEY ([ProfileCode], [InstanceCode])')

$template = 'line one' + $nl + 'line two ' + $eAcute + "`n" + 'tab' + "`t" + 'end' + $nl
$templateSha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::Unicode.GetBytes($template)))
$cr = @('RuleID', 'RuleCode', 'ExpectedTemplate', 'IsSensitive', 'ModifiedAt')
$data = ''
$data += 'SET IDENTITY_INSERT [cfg].[ConfigRule] ON;' + $nl
$data += New-Insert 'cfg' 'ConfigRule' $cr "10, N'PLAIN_RULE', N'plain Text Value', 0, '2026-01-02 03:04:05.1234567'"
$data += New-Insert 'cfg' 'ConfigRule' $cr "11, N'APP_CLIENT_SECRET', N'$markerA', 1, '2026-01-02 03:04:05.0000000'"
$data += 'SET IDENTITY_INSERT [cfg].[ConfigRule] OFF;' + $nl
$data += New-Insert 'cfg' 'LinksPageTemplate' @('TemplateCode', 'ContentTemplate', 'ContentSha256', 'IsEnabled') ("N'TPL', N'" + $template.Replace("'", "''") + "', N'$templateSha', 1")
$data += New-Insert 'ops' 'Engine' @('EngineCode', 'ScriptText', 'ScriptSha256', 'EngineVersion') "N'E1', N'engine text', N'$('0' * 64)', N'1.0'"
$srvCols = @('ServerCode', 'MachineName', 'ServicesRoot', 'IsEnabled', 'CreatedAt', 'ModifiedAt', 'ConfigBackupRoot', 'ManagementDatabaseName')
foreach ($sv in @(@('SRV_A', 'HOST-A'), @('SRV_B', 'HOST-B'), @('SRV_C', 'HOST-C'))) {
    $data += New-Insert 'dbo' 'ManagedServer' $srvCols ("N'{0}', N'{1}', N'D:\Services', 1, '2026-01-01 00:00:00.0000000', '2026-01-01 00:00:00.0000000', N'D:\Backups', N'_mgmt'" -f $sv[0], $sv[1])
}
foreach ($iv in @(@('A1', 'SRV_A'), @('A2', 'SRV_A'), @('B1', 'SRV_B'), @('B2', 'SRV_B'))) {
    $data += New-Insert 'dbo' 'ManagedInstance' @('InstanceCode', 'ServerCode', 'IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken', 'Notes') ("N'{0}', N'{1}', N'{2}', N'{2}', N'{2}', NULL" -f $iv[0], $iv[1], $markerC)
}
$data += New-Insert 'cfg' 'IisServerPolicy' @('ServerCode', 'ReconcileMode') "N'SRV_A', N'CREATE_AND_CORRECT'"
$data += New-Insert 'cfg' 'IisServerPolicy' @('ServerCode', 'ReconcileMode') "N'SRV_B', N'MISSING_SITES_ONLY'"
foreach ($lp in @(@('P1', 'A1'), @('P1', 'A2'), @('P1', 'B1'), @('P2', 'GHOST'))) {
    $data += New-Insert 'cfg' 'LinksProfileInstance' @('ProfileCode', 'InstanceCode', 'ModifiedAt') ("N'{0}', N'{1}', '2026-01-01 00:00:00.0000000'" -f $lp[0], $lp[1])
}
$fixture = '/* header */' + $nl + $ddl + $data

$script:CarriedTables = [ordered]@{
    'cfg.ConfigRule' = 'G'; 'cfg.LinksPageTemplate' = 'G'; 'ops.Engine' = 'G'
    'dbo.ManagedServer' = 'S'; 'cfg.IisServerPolicy' = 'S'
    'dbo.ManagedInstance' = 'I'; 'cfg.LinksProfileInstance' = 'I'
}
$schema = Read-SyncSchema -Text $fixture -Tables @($script:CarriedTables.Keys)
$source = [pscustomobject]@{ Schema = $schema; Rows = (Read-SyncRows -Text $fixture -Schema $schema) }

function Get-FailedGroups {
    param($Result)
    return @($Result.Checks | Where-Object { -not $_.ok } | ForEach-Object { $_.group } | Select-Object -Unique)
}
function Invoke-Tool {
    param([string]$Folder, [string[]]$Needles = @())
    return Invoke-CatalogConversionTest -Source $source -Folder $Folder -Sqlite3 $sqlite3 -ExtraNeedles $Needles 6>$null
}
function Copy-Folder {
    param([string]$From, [string]$To)
    Copy-Item -LiteralPath $From -Destination $To -Recurse
    return $To
}
function Invoke-Mutation {
    # Writes to a catalog of a copied folder (not read-only).
    param([string]$Folder, [string]$Catalog, [string]$Sql)
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $Folder $Catalog), $Sql))
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('tcc-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $info = @{ kind = 'test' }
    $cutDir = Join-Path $work 'cut'
    $null = Invoke-CutConversion -Source $source -SourceInfo $info -Folder $cutDir -Sqlite3 $sqlite3 -Codes @('ALL') -SourceRef 'tcc' 6>$null

    # 1. Intact catalogs pass ---------------------------------------------------------------------
    $ok = Invoke-Tool -Folder $cutDir -Needles @($markerA, $markerC)
    Assert-That 'intact cut catalogs: no check fails' ($ok.Failed -eq 0 -and $ok.Mode -eq 'cut' -and $ok.Catalogs -eq 3)
    Assert-That 'intact cut catalogs: all eight groups ran' (@(@('manifest', 'sqlite', 'exclusions', 'values', 'cut', 'global', 'secrets', 'stored-hash') | Where-Object { $g = $_; -not ($ok.Checks | Where-Object { $_.group -eq $g }) }).Count -eq 0)
    Assert-That 'intact cut catalogs: the stored hash of the multi-line template matches in every catalog' ((@($ok.Checks | Where-Object { $_.group -eq 'stored-hash' -and $_.ok })).Count -eq 1)
    $newDir = Join-Path $work 'new'
    $null = Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder $newDir -Sqlite3 $sqlite3 -Code 'NEW_SRV' -Machine 'NEW-HOST' -Services 'C:\S' -BackupRoot 'C:\B' -SourceRef 'tcc' 6>$null
    $okNew = Invoke-Tool -Folder $newDir -Needles @($markerA, $markerC)
    Assert-That 'intact new-machine catalog: no check fails' ($okNew.Failed -eq 0 -and $okNew.Mode -eq 'new-machine' -and $okNew.Catalogs -eq 1)

    # 2. Damage, one kind at a time ------------------------------------------------------------------
    $n = 0
    function New-Damaged { param($Name) $script:n++; return (Copy-Folder $cutDir (Join-Path $work ('d{0}-{1}' -f $script:n, $Name))) }

    $d = New-Damaged 'text'
    Invoke-Mutation $d 'catalog-SRV_A.db' "UPDATE cfg_ConfigRule SET ExpectedTemplate = 'plain text value' WHERE RuleCode = 'PLAIN_RULE';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'one text cell changed by a single letter case: values and manifest fail, and the table and key are named' ((Get-FailedGroups $r) -contains 'values' -and (Get-FailedGroups $r) -contains 'manifest' -and (@($r.Checks | Where-Object { -not $_.ok -and $_.group -eq 'values' -and $_.detail -like '*cfg_ConfigRule*different 1*10*' }).Count -eq 1))

    $d = New-Damaged 'crlf'
    Invoke-Mutation $d 'catalog-SRV_B.db' "UPDATE cfg_LinksPageTemplate SET ContentTemplate = replace(ContentTemplate, char(13) || char(10), char(10));"
    $r = Invoke-Tool -Folder $d
    Assert-That 'CRLF turned into LF in a multi-line text: caught by values and by the stored hash' ((Get-FailedGroups $r) -contains 'values' -and (Get-FailedGroups $r) -contains 'stored-hash')

    $d = New-Damaged 'row'
    Invoke-Mutation $d 'catalog-SRV_A.db' "DELETE FROM cfg_LinksProfileInstance WHERE InstanceCode = 'A2';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'a row missing in a catalog: values fail with the count' ((Get-FailedGroups $r) -contains 'values' -and (@($r.Checks | Where-Object { -not $_.ok -and $_.detail -like '*missing 1*' }).Count -ge 1))

    $d = New-Damaged 'foreign'
    Invoke-Mutation $d 'catalog-SRV_B.db' "INSERT INTO dbo_ManagedInstance (InstanceCode, ServerCode, Notes) VALUES ('A1', 'SRV_A', NULL);"
    $r = Invoke-Tool -Folder $d
    Assert-That 'an instance of another machine copied into a catalog: cut checks fail (in two catalogs, foreign row)' ((Get-FailedGroups $r) -contains 'cut' -and (@($r.Checks | Where-Object { -not $_.ok -and $_.check -like 'no instance is in two catalogs' }).Count -eq 1) -and (@($r.Checks | Where-Object { -not $_.ok -and $_.check -like 'no instance row belongs to another machine' }).Count -eq 1))

    $d = New-Damaged 'column'
    Invoke-Mutation $d 'catalog-SRV_C.db' 'ALTER TABLE dbo_ManagedInstance ADD COLUMN IisIdentityPassword TEXT;'
    $r = Invoke-Tool -Folder $d
    Assert-That 'a secret column added to a catalog: exclusions fail' ((Get-FailedGroups $r) -contains 'exclusions')

    $d = New-Damaged 'table'
    Invoke-Mutation $d 'catalog-SRV_C.db' 'CREATE TABLE sec_ManagedCredential (a TEXT) STRICT;'
    $r = Invoke-Tool -Folder $d
    Assert-That 'a table of the secret schema added: exclusions fail' ((Get-FailedGroups $r) -contains 'exclusions')

    $d = New-Damaged 'secret'
    Invoke-Mutation $d 'catalog-SRV_A.db' "UPDATE cfg_ConfigRule SET ExpectedTemplate = '$markerA' WHERE RuleCode = 'APP_CLIENT_SECRET';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'the original secret put back in a rule: secrets fail (needle found), values fail (not a reference token)' ((Get-FailedGroups $r) -contains 'secrets' -and (Get-FailedGroups $r) -contains 'values' -and (@($r.Checks | Where-Object { -not $_.ok -and $_.group -eq 'secrets' -and $_.detail -like '*catalog-SRV_A.db: 1 secret value(s) found*' }).Count -eq 1))

    $d = New-Damaged 'pattern'
    $planted = 'Pass' + 'word = ' + 'Wq9Xz4PlantedValue'
    Invoke-Mutation $d 'catalog-SRV_B.db' "UPDATE cfg_ConfigRule SET ExpectedTemplate = '$planted' WHERE RuleCode = 'PLAIN_RULE';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'a secret-like literal planted in a text cell: the pattern scan fails' (@($r.Checks | Where-Object { -not $_.ok -and $_.group -eq 'secrets' -and $_.check -like '*SRV_B*no secret-like literal*' }).Count -eq 1)

    $d = New-Damaged 'code'
    Invoke-Mutation $d 'catalog-SRV_A.db' "UPDATE dbo_ManagedServer SET ServerCode = 'srv_a';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'a code whose case was changed: values fail (stored case is compared exactly)' ((Get-FailedGroups $r) -contains 'values')

    $d = New-Damaged 'manifest'
    $mp = Join-Path $d 'conversion-manifest.json'
    $mt = [System.IO.File]::ReadAllText($mp)
    $m0 = [regex]::Match($mt, '"sha256":\s*"([0-9a-f]{8})')
    [System.IO.File]::WriteAllText($mp, $mt.Replace($m0.Groups[1].Value, '00000000'), [System.Text.UTF8Encoding]::new($false))
    $r = Invoke-Tool -Folder $d
    Assert-That 'a wrong SHA-256 in the manifest: manifest fails' ((Get-FailedGroups $r) -contains 'manifest' -and @(Get-FailedGroups $r).Count -eq 1)

    $d = New-Damaged 'stray'
    Copy-Item -LiteralPath (Join-Path $d 'catalog-SRV_A.db') -Destination (Join-Path $d 'catalog-EXTRA.db')
    $r = Invoke-Tool -Folder $d
    Assert-That 'an unlisted catalog file next to the others: manifest fails' ((Get-FailedGroups $r) -contains 'manifest')

    $d = New-Damaged 'global'
    Invoke-Mutation $d 'catalog-SRV_A.db' "UPDATE ops_Engine SET EngineVersion = '9.9' WHERE EngineCode = 'E1';"
    $r = Invoke-Tool -Folder $d
    Assert-That 'a global table changed in one catalog only: global and values fail' ((Get-FailedGroups $r) -contains 'global' -and (Get-FailedGroups $r) -contains 'values')

    $d = New-Damaged 'nomanifest'
    Remove-Item -LiteralPath (Join-Path $d 'conversion-manifest.json')
    $r = Invoke-Tool -Folder $d
    Assert-That 'a missing manifest: the tool fails instead of passing' ((Get-FailedGroups $r) -contains 'manifest')

    # 3. The tool never prints a value ------------------------------------------------------------------
    $d = New-Damaged 'noprint'
    Invoke-Mutation $d 'catalog-SRV_A.db' "UPDATE cfg_ConfigRule SET ExpectedTemplate = '$markerC' WHERE RuleCode = 'PLAIN_RULE';"
    $text = (Invoke-CatalogConversionTest -Source $source -Folder $d -Sqlite3 $sqlite3 -ExtraNeedles @($markerC) 6>&1 | Out-String)
    Assert-That 'the planted value is never printed (output carries names, keys and counts only)' (-not $text.Contains($markerC) -and $text.Contains('FAIL'))

    # 4. The source is not modified by the checks ----------------------------------------------------------
    Assert-That 'the in-memory source rows are unchanged after all runs' ($source.Rows['dbo.ManagedServer'].Count -eq 3 -and $source.Rows['dbo.ManagedServer'][0].Contains('ManagementDatabaseName') -and [string]$source.Rows['cfg.ConfigRule'][1]['ExpectedTemplate'] -ceq $markerA)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
