#requires -Version 7.0
<#
.SYNOPSIS
    Integration test of the SQL Server path of Export-ManagementEngines.ps1 and
    Convert-ManagementDb.ps1 against a real SQL Server engine (LocalDB on the CI runner).

.DESCRIPTION
    No real data is used. The 62 carried tables are created from the SHAPE stored in
    tests/Fixtures/carried-schema.json, in a database created with the collation
    Latin1_General_CI_AS, and filled with synthetic rows: multi-line text with CRLF, lone CR,
    lone LF, tabs, quotes, non-ASCII text, NULLs, binary values, decimals, GUIDs, 7-digit
    datetimes, identity values and marker values that stand in for secrets.

    The same rows are also written as a ManagementSync-style SQL file. Both tools run twice,
    once against SQL Server (-SqlInstance) and once against the file (-SyncFile). The two
    catalogs must be identical table by table (value by value, hashed from hex), and the two
    engine exports must be identical. The marker secrets must appear nowhere. The source
    database must be unchanged afterwards.

    -OfflineOnly skips everything that needs SQL Server (use it to check the fixture and the
    file path on any machine). Exit code: 0 pass, 1 failure, 2 environment problem.
#>
[CmdletBinding()]
param(
    [string]$SqlInstance = '(localdb)\MSSQLLocalDB',
    [string]$SqlClientPath,
    [Parameter(Mandatory)][string]$Sqlite3Path,
    [switch]$OfflineOnly,
    [switch]$KeepDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$exportTool = Join-Path $repo 'tools' 'Export-ManagementEngines.ps1'
$convertTool = Join-Path $repo 'tools' 'Convert-ManagementDb.ps1'
$verifyTool = Join-Path $repo 'tools' 'Test-CatalogConversion.ps1'
$schemaFile = Join-Path $repo 'tests' 'Fixtures' 'carried-schema.json'
# Dot-sourcing binds the tool's parameters into this scope, so keep our own values and restore them.
$savedSqlite3Path = $Sqlite3Path
$savedSqlClientPath = $SqlClientPath
$savedSqlInstance = $SqlInstance
. $convertTool -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'   # for $script:CarriedTables and helpers
$Sqlite3Path = $savedSqlite3Path
$SqlClientPath = $savedSqlClientPath
$SqlInstance = $savedSqlInstance
$classes = $script:CarriedTables
if (-not (Test-Path -LiteralPath $Sqlite3Path -PathType Leaf)) { Write-Host 'sqlite3 not found.'; exit 2 }
if (-not $OfflineOnly -and [string]::IsNullOrWhiteSpace($SqlClientPath)) { Write-Host '-SqlClientPath is required unless -OfflineOnly.'; exit 2 }

$script:Passed = 0
$script:Failures = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0} {1}' -f $Name, $Detail) }
}

# ---------------------------------------------------------------------------
# Fixture generation
# ---------------------------------------------------------------------------

$markerA = 'Zq8Lm2' + 'MARKERA' + '41'
$markerB = 'Rt5Vb9' + 'MARKERB' + '63'
$eAcute = [string][char]0x00E9
$cCedilla = [string][char]0x00C7
$schema = Get-Content -LiteralPath $schemaFile -Raw | ConvertFrom-Json
$rowsPerTable = 3

function Get-HashBytes {
    param([string]$Text)
    return [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
}
function Get-Sha256Hex {
    param([byte[]]$Bytes)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes))
}
function Get-FitText {
    param([string]$Base, [int]$Length, [int]$Index)
    $suffix = [string]$Index
    $max = 4000
    if ($Length -gt 0) { $max = $Length }
    if ($Base.Length + $suffix.Length -gt $max) { $Base = $Base.Substring(0, $max - $suffix.Length) }
    return $Base + $suffix
}

function New-CellValue {
    param($Table, $Column, [int]$Index, [bool]$IsKey)
    if ($Table.table -eq 'cfg.DatabaseObjectSettingRule' -and $Column.name -eq 'FilterClause') {
        if ($Index -eq 1) { return "[Section] = N'General'" }
        return "[Section] = N'General' AND [Key] = N'Fixture'"
    }
    $seed = '{0}|{1}|{2}' -f $Table.table, $Column.name, $Index
    switch ($Column.type) {
        'bit' { return [bool]($Index % 2) }
        'int' { return [int]($Index * 10) }
        'decimal' { return [decimal]::Round([decimal]($Index * 1.5 + 0.125), [int]$Column.scale) }
        'datetime2' { return [datetime]::new(2026, 1, $Index, 1, 2, 3).AddTicks(1234567) }
        'uniqueidentifier' { return [guid]::new([byte[]](Get-HashBytes $seed)[0..15]) }
        'varbinary' {
            $b = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0x0D, 0x0A, [byte]$Index)
            return , $b
        }
        'char' {
            switch ($Column.length) {
                2 { return @('PT', 'ES', 'BR')[$Index - 1] }
                7 { return '#1A2B3C' }
                64 { return [Convert]::ToHexString((Get-HashBytes $seed)) }
                default { return ('C' + $Index).PadRight($Column.length, 'x') }
            }
        }
        { $_ -in @('varchar', 'nvarchar', 'sysname') } {
            $length = [int]$Column.length
            if ($Column.type -eq 'sysname') { $length = 128 }
            $base = 'T' + ($Table.table -replace '[^A-Za-z0-9]', '') + $Column.name
            $unicode = ($Column.type -ne 'varchar')
            if (-not $IsKey -and $length -ne 0 -and ($length -lt 0 -or $length -ge 60)) {
                if ($Index -eq 2) {
                    $text = 'L1' + "`r`n" + 'L2 ' + $(if ($unicode) { $eAcute } else { 'e' }) + " 'q'" + "`n`t" + 'T' + "`r`n" + 'end' + "`r`n" + $Index
                    return $text
                }
                if ($Index -eq 3 -and $unicode) { return 'MiXeD-' + $cCedilla + $eAcute + '-' + $Index }
            }
            return Get-FitText -Base $base -Length $length -Index $Index
        }
        default { throw ('Unsupported fixture type: {0}' -f $Column.type) }
    }
}

function New-FixtureRows {
    $all = [ordered]@{}
    foreach ($table in $schema.tables) {
        $list = [System.Collections.Generic.List[object]]::new()
        for ($i = 1; $i -le $rowsPerTable; $i++) {
            $row = [ordered]@{}
            foreach ($col in $table.columns) {
                if ($col.type -eq 'timestamp') { continue }
                $isKey = @($table.primaryKey) -contains $col.name
                if ($col.identity) { $row[$col.name] = [int]$i; continue }
                if ($col.nullable -and -not $isKey -and $i -eq 3) { $row[$col.name] = $null; continue }
                $row[$col.name] = New-CellValue -Table $table -Column $col -Index $i -IsKey $isKey
            }
            # Table specific overrides
            switch ($table.table) {
                'cfg.ConfigRule' {
                    if ($i -eq 1) { $row['IsSensitive'] = $true; $row['ExpectedTemplate'] = 'Server={ServerName};Integrated Security=SSPI;' }
                    if ($i -eq 2) { $row['IsSensitive'] = $true; $row['RuleCode'] = 'FX_CLIENT_SECRET'; $row['ExpectedTemplate'] = $markerA }
                    if ($i -eq 3) { $row['IsSensitive'] = $false }
                }
                { $_ -in @('cfg.DatabaseObjectSettingRule', 'cfg.DatabaseSettingRule') } {
                    # A sensitive template is a "secret" for the verification tool: it must be unique, not generic text.
                    if ($row['IsSensitive'] -eq $true -and $null -ne $row['ExpectedTemplate']) { $row['ExpectedTemplate'] = 'FXRULESECRET-' + ($table.table -replace '[^A-Za-z0-9]', '') + '-' + $i }
                }
                'dbo.ManagedServer' { $row['ServerCode'] = 'FX_SRV' + $i; $row['MachineName'] = 'FX-HOST' + $i }
                { $_ -in @('cfg.IisServerPolicy', 'cfg.WebAccessPolicy', 'cfg.LinksPagePolicy', 'cfg.DatabaseCopyPolicy') } { $row['ServerCode'] = 'FX_SRV' + $i }
                'cfg.PulseProfile' { $row['HubInstanceCode'] = 'FX_INST' + $i }
                'sec.WindowsGroupPolicy' { $row['MachineName'] = 'FX-HOST' + $i }
                { $_ -in @('cfg.LinksPageInstanceApplication', 'ui.PublishedEnvironmentLink') } { $row['InstanceCode'] = 'FX_INST' + $i }
                'cfg.LinksProfileInstance' {
                    $row['InstanceCode'] = 'FX_INST' + $i
                    if ($i -eq 3) { $row['InstanceCode'] = 'FX_GHOST' }     # an orphan: belongs to no machine
                }
                'dbo.ManagedInstance' {
                    $row['InstanceCode'] = 'FX_INST' + $i
                    $row['ServerCode'] = 'FX_SRV' + $i
                    # Secret columns get values that occur nowhere else (the generic generator reuses the same text in
                    # many columns, which would be a false positive for the verification tool); row 3 keeps its NULLs.
                    foreach ($secretCol in @('IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken')) {
                        if ($i -eq 1) { $row[$secretCol] = $markerB }
                        elseif ($i -eq 2) { $row[$secretCol] = 'FXSECRET-' + $secretCol + '-' + $i }
                    }
                }
                'cfg.ConfigurationAdapterDefinition' {
                    $row['ActionCode'] = 'FX_ACTION_' + $i
                }
                'ops.Action' {
                    $row['ActionCode'] = 'FX_ACTION_' + $i
                    $row['EngineCode'] = 'FX_ENGINE_' + $i
                }
                'ops.Engine' {
                    $text = "# fixture engine $i`r`nWrite-Host 'it''s $i'`r`n# accent: $eAcute`r`n"
                    $row['EngineCode'] = 'FX_ENGINE_' + $i
                    $row['SourceFileName'] = 'Invoke-Fixture' + $i + '.ps1'
                    $row['ScriptText'] = $text
                    $row['ScriptSha256'] = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::Unicode.GetBytes($text)))
                }
                'cfg.LinksPageAsset' {
                    $bytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF, 0x0D, 0x0A, [byte]$i)
                    $row['Content'] = $bytes
                    $row['ContentSha256'] = Get-Sha256Hex $bytes
                }
            }
            $list.Add($row)
        }
        $all[$table.table] = $list
    }
    return $all
}

# ---------------------------------------------------------------------------
# Sync-file writer (same statement shape as the real ManagementSync.sql)
# ---------------------------------------------------------------------------

function Format-SqlTypeName {
    param($Column)
    switch ($Column.type) {
        { $_ -in @('varchar', 'nvarchar', 'char') } {
            if ($Column.length -lt 0) { return $Column.type + '(max)' }
            return '{0}({1})' -f $Column.type, $Column.length
        }
        'varbinary' { return 'varbinary(max)' }
        'decimal' { return 'decimal({0},{1})' -f $Column.precision, $Column.scale }
        default { return $Column.type }
    }
}

function ConvertTo-SyncLiteral {
    param($Value, $Column)
    if ($null -eq $Value) { return 'NULL' }
    switch ($Column.type) {
        'bit' { return $(if ($Value) { '1' } else { '0' }) }
        'int' { return ([int]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        'decimal' { return ([decimal]$Value).ToString('F' + $Column.scale, [System.Globalization.CultureInfo]::InvariantCulture) }
        'datetime2' { return "'" + ([datetime]$Value).ToString('yyyy-MM-dd HH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture) + "'" }
        'uniqueidentifier' { return "'" + ([guid]$Value).ToString('D').ToUpperInvariant() + "'" }
        'varbinary' { return '0x' + [Convert]::ToHexString([byte[]]$Value) }
        default { return "N'" + ([string]$Value).Replace("'", "''") + "'" }
    }
}

function New-SyncFileText {
    param($Fixture)
    $nl = "`r`n"
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('/* synthetic fixture in the shape of ManagementSync.sql */' + $nl)
    foreach ($table in $schema.tables) {
        $parts = $table.table.Split('.')
        [void]$sb.Append("IF OBJECT_ID('$($table.table)') IS NULL${nl}BEGIN${nl}    IF SCHEMA_ID('$($parts[0])') IS NULL EXEC('CREATE SCHEMA [$($parts[0])]');${nl}")
        [void]$sb.Append("    EXEC('CREATE TABLE [$($parts[0])].[$($parts[1])] (${nl}")
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($c in $table.columns) {
            $line = '    [{0}] {1}' -f $c.name, (Format-SqlTypeName $c)
            if ($c.identity) { $line += ' IDENTITY(1,1)' }
            $line += $(if ($c.nullable) { ' NULL' } else { ' NOT NULL' })
            $lines.Add($line)
        }
        $pkList = (@($table.primaryKey) | ForEach-Object { '[' + $_ + ']' }) -join ', '
        $lines.Add(('    CONSTRAINT [PK_{0}_sync] PRIMARY KEY ({1})' -f $parts[1], $pkList))
        [void]$sb.Append(($lines -join ",$nl") + "${nl})');${nl}END;${nl}${nl}")
    }
    foreach ($table in $schema.tables) {
        $parts = $table.table.Split('.')
        $byName = @{}
        foreach ($c in $table.columns) { $byName[$c.name] = $c }
        foreach ($row in $Fixture[$table.table]) {
            $names = @($row.Keys)
            $vals = foreach ($n in $names) { ConvertTo-SyncLiteral -Value $row[$n] -Column $byName[$n] }
            [void]$sb.Append(('INSERT INTO [{0}].[{1}] ({2}) VALUES ({3});' -f $parts[0], $parts[1], (($names | ForEach-Object { '[' + $_ + ']' }) -join ', '), ($vals -join ', ')) + $nl)
        }
    }
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# SQL Server side
# ---------------------------------------------------------------------------

function Get-Connection {
    param([string]$Database)
    $b = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $b['Data Source'] = $SqlInstance
    $b['Initial Catalog'] = $Database
    $b['Integrated Security'] = $true
    $b['Trust Server Certificate'] = $true
    $b['Connect Timeout'] = 30
    $c = [Microsoft.Data.SqlClient.SqlConnection]::new($b.ConnectionString)
    $c.Open()
    return $c
}
function Invoke-NonQuery {
    param($Connection, [string]$Sql)
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $Sql
    $cmd.CommandTimeout = 120
    [void]$cmd.ExecuteNonQuery()
}
function Invoke-Scalar {
    param($Connection, [string]$Sql)
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $Sql
    return $cmd.ExecuteScalar()
}

function New-SqlParameter {
    param([string]$Name, $Column, $Value)
    $type = [System.Data.SqlDbType]
    switch ($Column.type) {
        'bit' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::Bit) }
        'int' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::Int) }
        'decimal' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::Decimal); $p.Precision = [byte]$Column.precision; $p.Scale = [byte]$Column.scale }
        'datetime2' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::DateTime2) }
        'uniqueidentifier' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::UniqueIdentifier) }
        'varbinary' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::VarBinary, -1) }
        'char' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::Char, [int]$Column.length) }
        'varchar' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::VarChar, [int]$Column.length) }
        'nvarchar' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::NVarChar, [int]$Column.length) }
        'sysname' { $p = [Microsoft.Data.SqlClient.SqlParameter]::new($Name, $type::NVarChar, 128) }
        default { throw ('Unsupported type {0}' -f $Column.type) }
    }
    if ($null -eq $Value) { $p.Value = [System.DBNull]::Value } else { $p.Value = $Value }
    return $p
}

function New-SourceDatabase {
    param([string]$Name, $Fixture)
    $master = Get-Connection -Database 'master'
    try { Invoke-NonQuery $master ('CREATE DATABASE [{0}] COLLATE Latin1_General_CI_AS;' -f $Name); $script:dbCreated = $true } finally { $master.Dispose() }
    $c = Get-Connection -Database $Name
    try {
        foreach ($s in @('app', 'cfg', 'ops', 'sec', 'ui')) { Invoke-NonQuery $c ('CREATE SCHEMA [{0}];' -f $s) }
        foreach ($table in $schema.tables) {
            $parts = $table.table.Split('.')
            $defs = foreach ($col in $table.columns) {
                $d = '[{0}] {1}' -f $col.name, (Format-SqlTypeName $col)
                if ($col.identity) { $d += ' IDENTITY(1,1)' }
                if ($col.type -ne 'timestamp') { $d += $(if ($col.nullable) { ' NULL' } else { ' NOT NULL' }) } else { $d += ' NOT NULL' }
                $d
            }
            $pk = (@($table.primaryKey) | ForEach-Object { '[' + $_ + ']' }) -join ', '
            Invoke-NonQuery $c ('CREATE TABLE [{0}].[{1}] ({2}, CONSTRAINT [PK_{1}] PRIMARY KEY ({3}));' -f $parts[0], $parts[1], ($defs -join ', '), $pk)
        }
        foreach ($table in $schema.tables) {
            $parts = $table.table.Split('.')
            $byName = @{}
            foreach ($col in $table.columns) { $byName[$col.name] = $col }
            $hasIdentity = @($table.columns | Where-Object { $_.identity }).Count -gt 0
            foreach ($row in $Fixture[$table.table]) {
                $names = @($row.Keys)
                $cmd = $c.CreateCommand()
                $placeholders = for ($k = 0; $k -lt $names.Count; $k++) { '@p' + $k }
                $sql = 'INSERT INTO [{0}].[{1}] ({2}) VALUES ({3});' -f $parts[0], $parts[1], (($names | ForEach-Object { '[' + $_ + ']' }) -join ', '), ($placeholders -join ', ')
                if ($hasIdentity) { $sql = ('SET IDENTITY_INSERT [{0}].[{1}] ON; ' -f $parts[0], $parts[1]) + $sql + (' SET IDENTITY_INSERT [{0}].[{1}] OFF;' -f $parts[0], $parts[1]) }
                $cmd.CommandText = $sql
                for ($k = 0; $k -lt $names.Count; $k++) {
                    [void]$cmd.Parameters.Add((New-SqlParameter -Name ('@p' + $k) -Column $byName[$names[$k]] -Value $row[$names[$k]]))
                }
                [void]$cmd.ExecuteNonQuery()
            }
        }
    }
    finally { $c.Dispose() }
}

function Get-SourceFingerprint {
    # Row counts and a checksum per table, to prove the tools did not change the source.
    param([string]$Name)
    $c = Get-Connection -Database $Name
    try {
        $result = [ordered]@{}
        foreach ($table in $schema.tables) {
            $parts = $table.table.Split('.')
            $cols = (@($table.columns | Where-Object { $_.type -ne 'timestamp' } | ForEach-Object { '[' + $_.name + ']' }) -join ', ')
            $result[$table.table] = [string](Invoke-Scalar $c ('SELECT CONCAT(COUNT_BIG(*), ''|'', CHECKSUM_AGG(CHECKSUM({2}))) FROM [{0}].[{1}];' -f $parts[0], $parts[1], $cols))
        }
        return $result
    }
    finally { $c.Dispose() }
}

# ---------------------------------------------------------------------------
# Running the tools and comparing catalogs
# ---------------------------------------------------------------------------

$pwsh = (Get-Process -Id $PID).Path
function Invoke-Tool {
    param([string]$Path, [string[]]$Arguments)
    $out = & $pwsh -NoProfile -File $Path @Arguments 2>&1 | Out-String
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $out }
}
function Get-TextFromSqlite {
    param([string]$Db, [string]$Sql)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Sqlite3Path)
    $psi.ArgumentList.Add('-readonly'); $psi.ArgumentList.Add($Db); $psi.ArgumentList.Add($Sql)
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $o = $proc.StandardOutput.ReadToEndAsync(); $e = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw ('sqlite3 failed: ' + $e.GetAwaiter().GetResult()) }
    return $o.GetAwaiter().GetResult()
}
function Get-CatalogDigests {
    # Per table: SHA-256 over the sorted rows, each cell as typeof:hex, so no byte can be altered unseen.
    # The new ManagedServer row gets CreatedAt and ModifiedAt from the clock at conversion time, so those
    # two columns are left out of the comparison (they differ between any two runs by design).
    param([string]$Db, [switch]$IncludeClock)
    $skip = @{ 'dbo_ManagedServer' = @('CreatedAt', 'ModifiedAt') }
    if ($IncludeClock) { $skip = @{} }
    $digests = [ordered]@{}
    $tables = @((Get-TextFromSqlite $Db "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;") -split "`n" | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
    foreach ($t in $tables) {
        $cols = @((Get-TextFromSqlite $Db ("SELECT name FROM pragma_table_info('{0}') ORDER BY cid;" -f $t)) -split "`n" | Where-Object { $_.Trim().Length -gt 0 } | ForEach-Object { $_.Trim() })
        if ($skip.ContainsKey($t)) { $cols = @($cols | Where-Object { $skip[$t] -notcontains $_ }) }
        $expr = ($cols | ForEach-Object { "typeof(`"$_`") || ':' || hex(`"$_`")" }) -join " || '|' || "
        $text = Get-TextFromSqlite $Db ("SELECT {0} AS r FROM `"{1}`" ORDER BY r;" -f $expr, $t)
        $digests[$t] = Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($text))
    }
    return $digests
}
function Test-FileContains {
    param([string]$Path, [string]$Needle)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return [System.Text.Encoding]::Latin1.GetString($bytes).Contains($Needle)
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('sqlserver-path-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$dbName = 'sisqual_fx_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$dbCreated = $false
try {
    # 1. Fixture and file path ----------------------------------------------------------
    $fixture = New-FixtureRows
    $syncText = New-SyncFileText -Fixture $fixture
    $syncPath = Join-Path $work 'fixture-sync.sql'
    [System.IO.File]::WriteAllText($syncPath, $syncText, [System.Text.UTF8Encoding]::new($false))
    Assert-That 'fixture: 62 tables, 3 rows each' ($fixture.Count -eq 62 -and @($fixture.Values | Where-Object { $_.Count -ne 3 }).Count -eq 0)

    $newMachineArgs = @('-NewMachine', '-ServerCode', 'NEW01', '-MachineName', 'NEW-HOST', '-ServicesRoot', 'C:\Services', '-ConfigBackupRoot', 'C:\Backups', '-Sqlite3Path', $Sqlite3Path)
    $outFile = Join-Path $work 'convert-file'
    $rFile = Invoke-Tool $convertTool (@('-SyncFile', $syncPath, '-OutputFolder', $outFile) + $newMachineArgs)
    Assert-That 'file path: conversion succeeds' ($rFile.ExitCode -eq 0) $rFile.Output.Substring(0, [Math]::Min(600, $rFile.Output.Length))
    $dbFile = Join-Path $outFile 'catalog-NEW01.db'
    if ($rFile.ExitCode -ne 0) { throw 'file path conversion failed' }

    $manifestFile = [System.IO.File]::ReadAllText((Join-Path $outFile 'conversion-manifest.json')) | ConvertFrom-Json
    $entryFile = $manifestFile.catalogs[0]
    $expectedRows = 0
    foreach ($t in $classes.Keys) { if ($classes[$t] -eq 'G') { $expectedRows += 3 } }
    Assert-That 'file path: the new server row has creation times from the clock' ((Get-TextFromSqlite $dbFile "SELECT count(*) FROM dbo_ManagedServer WHERE CreatedAt LIKE '20%T%' AND ModifiedAt LIKE '20%T%';").Trim() -eq '1')
    Assert-That 'file path: every global table carries its 3 rows, cut tables are empty, one server row' ((($entryFile.tables | Measure-Object destinationRows -Sum).Sum) -eq ($expectedRows + 1))
    $expectedMulti = 'L1' + "`r`n" + 'L2 ' + $eAcute + " 'q'" + "`n`t" + 'T' + "`r`n" + 'end' + "`r`n" + '2'
    $expectedHex = [Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes($expectedMulti))
    Assert-That 'file path: multi-line text with CRLF, lone LF, tab, quote and accent is byte-exact' ((Get-TextFromSqlite $dbFile "SELECT hex(ResourceValue) FROM ui_Resource WHERE ResourceValue LIKE 'L1%';").Trim() -eq $expectedHex)
    foreach ($m in @($markerA, $markerB)) {
        Assert-That ('file path: marker not in the catalog: ' + $m.Substring(6, 7)) (-not (Test-FileContains $dbFile $m))
    }
    Assert-That 'file path: the redacted rule is reported by code' (@($entryFile.redactedRules | Where-Object { $_ -like '*FX_CLIENT_SECRET*' }).Count -eq 1)
    $engFile = Join-Path $work 'export-file'
    $eFile = Invoke-Tool $exportTool @('-SyncFile', $syncPath, '-OutputFolder', $engFile)
    Assert-That 'file path: engine export succeeds with 3 engines' ($eFile.ExitCode -eq 0 -and (@(Get-ChildItem $engFile -Filter 'Invoke-Fixture*.ps1').Count -eq 3)) $eFile.Output

    # 1b. Cut mode, file path ---------------------------------------------------------------
    $outCutFile = Join-Path $work 'cut-file'
    $rCutFile = Invoke-Tool $convertTool @('-SyncFile', $syncPath, '-OutputFolder', $outCutFile, '-Sqlite3Path', $Sqlite3Path)
    Assert-That 'cut, file path: conversion of all machines succeeds' ($rCutFile.ExitCode -eq 0) $rCutFile.Output.Substring(0, [Math]::Min(700, $rCutFile.Output.Length))
    if ($rCutFile.ExitCode -ne 0) { throw 'cut conversion from the file failed' }
    $cutManifestFile = [System.IO.File]::ReadAllText((Join-Path $outCutFile 'conversion-manifest.json')) | ConvertFrom-Json
    Assert-That 'cut, file path: three catalogs, mode cut, each instance in exactly one catalog' ($cutManifestFile.mode -eq 'cut' -and @($cutManifestFile.catalogs).Count -eq 3 -and $cutManifestFile.completeness.eachInstanceInExactlyOneCatalog -and $cutManifestFile.completeness.instancesInSource -eq 3)
    $cutCounts = @()
    foreach ($n in 1..3) {
        $dbc = Join-Path $outCutFile ('catalog-FX_SRV{0}.db' -f $n)
        $cutCounts += (Get-TextFromSqlite $dbc 'SELECT (SELECT count(*) FROM dbo_ManagedServer) || (SELECT count(*) FROM dbo_ManagedInstance) || (SELECT count(*) FROM cfg_IisServerPolicy) || (SELECT count(*) FROM cfg_PulseProfile) || (SELECT count(*) FROM sec_WindowsGroupPolicy) || (SELECT count(*) FROM ui_PublishedEnvironmentLink) || (SELECT count(*) FROM cfg_LinksPageInstanceApplication) || (SELECT count(*) FROM cfg_LinksProfileInstance);').Trim()
    }
    Assert-That 'cut, file path: every machine gets its own rows; the orphan profile link is dropped (machine 3 has none)' (($cutCounts -join ',') -eq '11111111,11111111,11111110') ($cutCounts -join ',')
    Assert-That 'cut, file path: the orphan is reported with its code' (@($cutManifestFile.unplaced | Where-Object { $_ -like 'cfg_LinksProfileInstance: 1 row(s)*FX_GHOST*' }).Count -eq 1)
    $g1 = Get-CatalogDigests (Join-Path $outCutFile 'catalog-FX_SRV1.db') -IncludeClock
    $g2 = Get-CatalogDigests (Join-Path $outCutFile 'catalog-FX_SRV2.db') -IncludeClock
    $globalDiff = @($classes.Keys | Where-Object { $classes[$_] -eq 'G' } | ForEach-Object { $_ -replace '\.', '_' } | Where-Object { $g1[$_] -ne $g2[$_] })
    Assert-That 'cut, file path: global tables are identical in every catalog' ($globalDiff.Count -eq 0) ($globalDiff -join ', ')
    foreach ($m in @($markerA, $markerB)) {
        Assert-That ('cut, file path: marker not in any catalog: ' + $m.Substring(6, 7)) (-not (@(1..3) | Where-Object { Test-FileContains (Join-Path $outCutFile ('catalog-FX_SRV{0}.db' -f $_)) $m }))
    }

    # 1c. The verification tool, file path ----------------------------------------------------------
    $vNewFile = Invoke-Tool $verifyTool @('-SyncFile', $syncPath, '-CatalogFolder', $outFile, '-Sqlite3Path', $Sqlite3Path)
    Assert-That 'verify, file path: Test-CatalogConversion passes on the new-machine catalog' ($vNewFile.ExitCode -eq 0) ($vNewFile.Output -split "`n" | Where-Object { $_ -match '^FAIL' } | Select-Object -First 3 | Out-String)
    $vCutFile = Invoke-Tool $verifyTool @('-SyncFile', $syncPath, '-CatalogFolder', $outCutFile, '-Sqlite3Path', $Sqlite3Path)
    Assert-That 'verify, file path: Test-CatalogConversion passes on the three cut catalogs (every cell of every table)' ($vCutFile.ExitCode -eq 0) ($vCutFile.Output -split "`n" | Where-Object { $_ -match '^FAIL' } | Select-Object -First 3 | Out-String)

    if (-not $OfflineOnly) {
        # 2. SQL Server ----------------------------------------------------------------
        $dll = Join-Path $SqlClientPath 'Microsoft.Data.SqlClient.dll'
        Add-Type -Path $dll
        New-SourceDatabase -Name $dbName -Fixture $fixture
        $dbCreated = $true
        $before = Get-SourceFingerprint -Name $dbName
        $collation = ''
        $cc = Get-Connection -Database $dbName
        try { $collation = [string](Invoke-Scalar $cc "SELECT CONVERT(nvarchar(128), DATABASEPROPERTYEX(DB_NAME(), 'Collation'));") } finally { $cc.Dispose() }
        Assert-That 'sql: the fixture database has the collation Latin1_General_CI_AS' ($collation -eq 'Latin1_General_CI_AS') $collation
        Assert-That 'sql: 62 tables loaded' (($before.Keys | Measure-Object).Count -eq 62)

        $sqlArgs = @('-SqlInstance', $SqlInstance, '-Database', $dbName, '-SqlClientPath', $SqlClientPath, '-TrustServerCertificate')
        $outSql = Join-Path $work 'convert-sql'
        $rSql = Invoke-Tool $convertTool (@($sqlArgs) + @('-OutputFolder', $outSql) + $newMachineArgs)
        Assert-That 'sql: conversion succeeds' ($rSql.ExitCode -eq 0) $rSql.Output.Substring(0, [Math]::Min(900, $rSql.Output.Length))
        if ($rSql.ExitCode -eq 0) {
            $dbSql = Join-Path $outSql 'catalog-NEW01.db'
            $manifestSql = [System.IO.File]::ReadAllText((Join-Path $outSql 'conversion-manifest.json')) | ConvertFrom-Json
            Assert-That 'sql: the tool read the collation from the database' ($manifestSql.sourceCollation -eq 'Latin1_General_CI_AS') ([string]$manifestSql.sourceCollation)
            Assert-That 'sql: row counts per table equal the file path' ((($manifestSql.catalogs[0].tables | ConvertTo-Json -Depth 5 -Compress) -eq ($entryFile.tables | ConvertTo-Json -Depth 5 -Compress)))
            $dFile = Get-CatalogDigests $dbFile
            $dSql = Get-CatalogDigests $dbSql
            $diff = @($dFile.Keys | Where-Object { $_ -ne 'catalog_meta' -and $dFile[$_] -ne $dSql[$_] })
            Assert-That 'sql: the catalog is identical to the one built from the file, value by value, in every table' ($diff.Count -eq 0 -and $dFile.Count -eq $dSql.Count) ($diff -join ', ')
            foreach ($m in @($markerA, $markerB)) {
                Assert-That ('sql: marker not in the catalog: ' + $m.Substring(6, 7)) (-not (Test-FileContains $dbSql $m))
                Assert-That ('sql: marker not in the manifest: ' + $m.Substring(6, 7)) (-not (Test-FileContains (Join-Path $outSql 'conversion-manifest.json') $m))
            }
            Assert-That 'sql: the same rules are redacted as in the file path' ((($manifestSql.catalogs[0].redactedRules | ConvertTo-Json -Compress) -eq ($entryFile.redactedRules | ConvertTo-Json -Compress)) -and $manifestSql.catalogs[0].redactedRuleCount -ge 1)
        }

        $outEng = Join-Path $work 'export-sql'
        $eSql = Invoke-Tool $exportTool (@($sqlArgs) + @('-OutputFolder', $outEng))
        Assert-That 'sql: engine export succeeds' ($eSql.ExitCode -eq 0) $eSql.Output.Substring(0, [Math]::Min(900, $eSql.Output.Length))
        if ($eSql.ExitCode -eq 0) {
            $same = $true
            foreach ($f in (Get-ChildItem $engFile -Filter 'Invoke-Fixture*.ps1')) {
                $other = Join-Path $outEng $f.Name
                if (-not (Test-Path $other) -or ((Get-FileHash $other -Algorithm SHA256).Hash -ne (Get-FileHash $f.FullName -Algorithm SHA256).Hash)) { $same = $false }
            }
            Assert-That 'sql: the exported engine files are identical to the file path (CRLF, accents)' $same
            $mSql = [System.IO.File]::ReadAllText((Join-Path $outEng 'engines-export-manifest.json')) | ConvertFrom-Json
            Assert-That 'sql: 3 engines, no hash mismatch' ($mSql.engineCount -eq 3 -and $mSql.hashMismatches -eq 0)
        }

        # 2b. Cut mode against SQL Server: every catalog must equal the one built from the file ---
        $outCutSql = Join-Path $work 'cut-sql'
        $rCutSql = Invoke-Tool $convertTool (@($sqlArgs) + @('-OutputFolder', $outCutSql, '-Sqlite3Path', $Sqlite3Path))
        Assert-That 'cut, sql: conversion of all machines succeeds' ($rCutSql.ExitCode -eq 0) $rCutSql.Output.Substring(0, [Math]::Min(900, $rCutSql.Output.Length))
        if ($rCutSql.ExitCode -eq 0) {
            $cutManifestSql = [System.IO.File]::ReadAllText((Join-Path $outCutSql 'conversion-manifest.json')) | ConvertFrom-Json
            Assert-That 'cut, sql: the tool read the collation from the database and the completeness check passed' ($cutManifestSql.sourceCollation -eq 'Latin1_General_CI_AS' -and $cutManifestSql.completeness.eachInstanceInExactlyOneCatalog)
            $cutDiff = @()
            foreach ($n in 1..3) {
                $a = Get-CatalogDigests (Join-Path $outCutFile ('catalog-FX_SRV{0}.db' -f $n)) -IncludeClock
                $b = Get-CatalogDigests (Join-Path $outCutSql ('catalog-FX_SRV{0}.db' -f $n)) -IncludeClock
                $cutDiff += @($a.Keys | Where-Object { $_ -ne 'catalog_meta' -and $a[$_] -ne $b[$_] } | ForEach-Object { 'FX_SRV{0}:{1}' -f $n, $_ })
                if ($a.Count -ne $b.Count) { $cutDiff += ('FX_SRV{0}: different table count' -f $n) }
            }
            Assert-That 'cut, sql: all three catalogs are identical to the ones built from the file, value by value, clock columns included' ($cutDiff.Count -eq 0) ($cutDiff -join ', ')
            Assert-That 'cut, sql: the same unplaced rows and the same completeness counts as the file path' ((($cutManifestSql.unplaced | ConvertTo-Json -Compress) -eq ($cutManifestFile.unplaced | ConvertTo-Json -Compress)) -and (($cutManifestSql.completeness.tables | ConvertTo-Json -Depth 5 -Compress) -eq ($cutManifestFile.completeness.tables | ConvertTo-Json -Depth 5 -Compress)))
            foreach ($m in @($markerA, $markerB)) {
                Assert-That ('cut, sql: marker not in any catalog or manifest: ' + $m.Substring(6, 7)) (-not (@(1..3) | Where-Object { Test-FileContains (Join-Path $outCutSql ('catalog-FX_SRV{0}.db' -f $_)) $m }) -and -not (Test-FileContains (Join-Path $outCutSql 'conversion-manifest.json') $m))
            }
        }

        # 2c. The verification tool against the SQL Server source ---------------------------------
        $vNewSql = Invoke-Tool $verifyTool (@($sqlArgs) + @('-CatalogFolder', $outSql, '-Sqlite3Path', $Sqlite3Path))
        Assert-That 'verify, sql: Test-CatalogConversion passes on the new-machine catalog, read from SQL Server' ($vNewSql.ExitCode -eq 0) ($vNewSql.Output -split "`n" | Where-Object { $_ -match '^FAIL' } | Select-Object -First 3 | Out-String)
        $vCutSql = Invoke-Tool $verifyTool (@($sqlArgs) + @('-CatalogFolder', $outCutSql, '-Sqlite3Path', $Sqlite3Path))
        Assert-That 'verify, sql: Test-CatalogConversion passes on the cut catalogs, read from SQL Server' ($vCutSql.ExitCode -eq 0) ($vCutSql.Output -split "`n" | Where-Object { $_ -match '^FAIL' } | Select-Object -First 3 | Out-String)

        # 3. The source must not change -------------------------------------------------
        $after = Get-SourceFingerprint -Name $dbName
        $changed = @($before.Keys | Where-Object { $before[$_] -ne $after[$_] })
        Assert-That 'sql: the tools did not change the source database (counts and checksums)' ($changed.Count -eq 0) ($changed -join ', ')

        # 4. Informational: the default connection validates the server certificate -------
        $strict = Invoke-Tool $exportTool @('-SqlInstance', $SqlInstance, '-Database', $dbName, '-SqlClientPath', $SqlClientPath, '-OutputFolder', (Join-Path $work 'strict'))
        Write-Host ('INFO  without -TrustServerCertificate the export exit code is {0} (LocalDB certificate)' -f $strict.ExitCode)
    }
}
catch {
    $script:Failures++
    Write-Host ('FAIL  unexpected error: {0}' -f $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
}
finally {
    if ($dbCreated -and -not $KeepDatabase) {
        try {
            $m = Get-Connection -Database 'master'
            try { Invoke-NonQuery $m ('ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}];' -f $dbName) } finally { $m.Dispose() }
        }
        catch { Write-Host ('INFO  could not drop {0}: {1}' -f $dbName, $_.Exception.Message) }
    }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
