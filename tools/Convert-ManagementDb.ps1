#requires -Version 7.0
<#
.SYNOPSIS
    Converts the _sisqualMANAGEMENT configuration into a read-only SQLite catalog for ONE machine.

.DESCRIPTION
    Step B2 of docs/migration/catalog-conversion-plan.md (approved 2026-10-05).
    This version implements the NEW-MACHINE mode: all global tables are copied, the cut
    tables (by ServerCode / InstanceCode) are created EMPTY, and one dbo_ManagedServer row
    is built from the parameters. The cut mode for existing machines is step B3.

    Sources (read only):
      -SyncFile    a ManagementSync.sql file (offline).
      -SqlInstance SQL Server through Microsoft.Data.SqlClient (ApplicationIntent=ReadOnly,
                   integrated security). [V] not tested against a real server.

    Rules applied (plan sections 1 to 3):
      - only the 62 whitelisted tables are read; nothing else is touched;
      - secret columns, rowversion columns and ops.Engine script text are not carried;
      - literal secrets inside sensitive rule templates are replaced by a reference token;
      - a safety-net scan refuses to write a catalog if a secret-like literal remains;
      - tables are created STRICT with the sqlite3 executable given in -Sqlite3Path
        (the pinned 3.53.4); no managed SQLite provider is used.

    Output: catalog-<ServerCode>.db and conversion-manifest.json (SHA-256, row counts,
    findings, redaction rule codes). No value of any secret is ever printed or written.
#>
[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Sync')]
    [string]$SyncFile,

    [Parameter(Mandatory, ParameterSetName = 'Sql')]
    [string]$SqlInstance,

    [Parameter(ParameterSetName = 'Sql')]
    [string]$Database = '_sisqualMANAGEMENT',

    [Parameter(Mandatory, ParameterSetName = 'Sql')]
    [string]$SqlClientPath,

    # Off by default: the server certificate is validated. LocalDB and test servers need it on.
    # The setting for the real SISQUAL servers is decided against a real server [V].
    [Parameter(ParameterSetName = 'Sql')]
    [switch]$TrustServerCertificate,

    [Parameter(Mandatory)]
    [string]$OutputFolder,

    [Parameter(Mandatory)]
    [string]$Sqlite3Path,

    [switch]$NewMachine,
    [string]$ServerCode,
    [string]$MachineName,
    [string]$ServicesRoot,
    [string]$ConfigBackupRoot,

    [string]$SourceReference = '',

    # Binary (default) compares text exactly, like SQLite does by default. NoCase declares every
    # text column whose name ends in Code as COLLATE NOCASE (ASCII folding only).
    [ValidateSet('Binary', 'NoCase')]
    [string]$CodeCollation = 'Binary'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolVersion = '0.2.0'
$script:SchemaVersion = 1
$script:CutRuleVersion = 1

# Class: G = global, S = cut by ServerCode, I = cut by InstanceCode (plan section 1.3, 62 tables).
$script:CarriedTables = [ordered]@{}
foreach ($t in @(
        'app.ActionRuntimePolicy', 'app.DatabaseCopyDatabaseDefinition', 'app.DatabaseCopyPolicy',
        'app.EnvironmentCloneProfile', 'app.HousekeepingPolicy', 'app.Product', 'app.VersionBaseline',
        'cfg.Application', 'cfg.ApplicationCopyPolicy', 'cfg.ConfigFile', 'cfg.ConfigFileRepairPolicy',
        'cfg.ConfigRule', 'cfg.ConfigurationAdapterDefinition', 'cfg.DatabaseDefinition',
        'cfg.DatabaseObjectSettingRule', 'cfg.DatabaseSettingRule', 'cfg.EnvironmentCloneDatabasePolicy',
        'cfg.IisApplicationAutoStartDefinition', 'cfg.IisApplicationDefinition', 'cfg.IisBindingDefinition',
        'cfg.IisDirectoryDefinition', 'cfg.IisPrerequisiteDefinition', 'cfg.IisServiceAutoStartProviderDefinition',
        'cfg.KeycloakClientSecretRule', 'cfg.LinksPageAsset', 'cfg.LinksPagePresentationResource',
        'cfg.LinksPageTemplate', 'cfg.LinksProfile', 'cfg.LinksProfileApplication', 'cfg.ManagedAssetDestination',
        'cfg.PulseHttpPolicy', 'cfg.PulseResource', 'cfg.SettingDefinition', 'cfg.SettingSection',
        'cfg.SettingValue', 'cfg.WebAccessTemplate', 'cfg.WebsiteBrandingAsset', 'cfg.WebsiteBrandingProfile',
        'cfg.WebsiteFolderCopyPolicy', 'cfg.WindowsServiceDefinition',
        'ops.Action', 'ops.ActionRequirement', 'ops.ActionStep', 'ops.ActionUiMetadata', 'ops.ConsoleProfile',
        'ops.Engine', 'ops.MenuGroup', 'ops.ReviewDefinition', 'sec.Policy', 'ui.NavigationItem', 'ui.Resource'
    )) { $script:CarriedTables[$t] = 'G' }
foreach ($t in @('dbo.ManagedServer', 'cfg.IisServerPolicy', 'cfg.WebAccessPolicy', 'cfg.LinksPagePolicy',
        'cfg.DatabaseCopyPolicy', 'cfg.PulseProfile', 'sec.WindowsGroupPolicy')) { $script:CarriedTables[$t] = 'S' }
foreach ($t in @('dbo.ManagedInstance', 'cfg.LinksPageInstanceApplication', 'cfg.LinksProfileInstance',
        'ui.PublishedEnvironmentLink')) { $script:CarriedTables[$t] = 'I' }

# Columns never carried (plan section 3.2). Excluded by NAME, never by value.
$script:ExcludedColumns = @{
    'dbo.ManagedInstance' = @('IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken')
    'ops.Engine'          = @('ScriptText', 'ScriptSha256')
    # Names the old central database; it ceases to exist (owner answer of 2026-10-05).
    'dbo.ManagedServer'   = @('ManagementDatabaseName')
}

# Rule tables whose sensitive templates may hold a literal secret (plan section 3.3).
$script:RedactionTables = @{
    'cfg.ConfigRule'                = @{ Template = 'ExpectedTemplate'; Id = 'RuleCode' }
    'cfg.DatabaseObjectSettingRule' = @{ Template = 'ExpectedTemplate'; Id = 'SettingCode' }
    'cfg.DatabaseSettingRule'       = @{ Template = 'ExpectedTemplate'; Id = 'SettingCode' }
}
$script:PlaceholderPattern = '\{[A-Za-z_][\w.]*\}|\{\{|\$\(|%[A-Za-z_]+%|<[A-Za-z_]+>'

# ---------------------------------------------------------------------------
# Quote-aware SQL text scanning (offline source)
# ---------------------------------------------------------------------------

function Skip-SqlString {
    # $Position is the opening quote. Returns the index after the closing quote.
    param([string]$Text, [int]$Position)
    $start = $Position + 1
    while ($true) {
        $quote = $Text.IndexOf("'", $start, [System.StringComparison]::Ordinal)
        if ($quote -lt 0) { throw 'Unterminated string literal.' }
        if ($quote + 1 -lt $Text.Length -and $Text[$quote + 1] -eq "'") { $start = $quote + 2; continue }
        return $quote + 1
    }
}

function Read-SqlStringValue {
    param([string]$Text, [int]$QuotePosition)
    $builder = [System.Text.StringBuilder]::new()
    $start = $QuotePosition + 1
    while ($true) {
        $quote = $Text.IndexOf("'", $start, [System.StringComparison]::Ordinal)
        if ($quote -lt 0) { throw 'Unterminated string literal.' }
        [void]$builder.Append($Text, $start, $quote - $start)
        if ($quote + 1 -lt $Text.Length -and $Text[$quote + 1] -eq "'") { [void]$builder.Append("'"); $start = $quote + 2; continue }
        return [pscustomobject]@{ Value = $builder.ToString(); Next = $quote + 1 }
    }
}

function Find-ValuesEnd {
    # $Position is just after "VALUES (". Returns the index of the closing ")".
    param([string]$Text, [int]$Position)
    $i = $Position
    $depth = 0
    $stops = [char[]]@([char]"'", [char]'(', [char]')')
    while ($true) {
        $j = $Text.IndexOfAny($stops, $i)
        if ($j -lt 0) { throw 'Unterminated VALUES list.' }
        $c = $Text[$j]
        if ($c -eq "'") { $i = Skip-SqlString -Text $Text -Position $j; continue }
        if ($c -eq '(') { $depth++; $i = $j + 1; continue }
        if ($depth -eq 0) { return $j }
        $depth--
        $i = $j + 1
    }
}

function Read-SqlValue {
    # Reads one literal. Returns the raw value (string, byte[], long/decimal text or $null) and the next index.
    param([string]$Text, [int]$Position)
    $i = $Position
    while ($Text[$i] -eq ' ') { $i++ }
    $c = $Text[$i]
    if ($c -eq 'N' -and $Text[$i + 1] -eq "'") {
        $r = Read-SqlStringValue -Text $Text -QuotePosition ($i + 1)
        return [pscustomobject]@{ Kind = 'S'; Value = $r.Value; Next = $r.Next }
    }
    if ($c -eq "'") {
        $r = Read-SqlStringValue -Text $Text -QuotePosition $i
        return [pscustomobject]@{ Kind = 'S'; Value = $r.Value; Next = $r.Next }
    }
    if ($c -eq '0' -and $Text[$i + 1] -eq 'x') {
        $j = $i + 2
        while ($j -lt $Text.Length -and [Uri]::IsHexDigit($Text[$j])) { $j++ }
        $hex = $Text.Substring($i + 2, $j - $i - 2)
        # Assign inside the branches: an `if` expression would unroll the byte[] into an object[].
        [byte[]]$bytes = [byte[]]::new(0)
        if ($hex.Length -gt 0) { $bytes = [Convert]::FromHexString($hex) }
        return [pscustomobject]@{ Kind = 'B'; Value = $bytes; Next = $j }
    }
    if ($c -eq 'N' -and $Text.Substring($i, 4) -ceq 'NULL') {
        return [pscustomobject]@{ Kind = 'Z'; Value = $null; Next = $i + 4 }
    }
    $j = $i
    while ($j -lt $Text.Length -and '-0123456789.eE+'.IndexOf($Text[$j]) -ge 0) { $j++ }
    if ($j -eq $i) { throw ('Unsupported value at offset {0}.' -f $i) }
    return [pscustomobject]@{ Kind = 'N'; Value = $Text.Substring($i, $j - $i); Next = $j }
}

# ---------------------------------------------------------------------------
# Source adapter: sync file
# ---------------------------------------------------------------------------

function ConvertTo-ColumnInfo {
    param([string]$Line)
    $m = [regex]::Match($Line, '^\s*\[(\w+)\]\s+(\w+)(?:\(([^)]*)\))?\s*(IDENTITY\s*\(\s*\d+\s*,\s*\d+\s*\))?\s*(NOT NULL|NULL)')
    if (-not $m.Success) { return $null }
    $args = $m.Groups[3].Value
    $length = 0
    $precision = 0
    $scale = 0
    if ($args -match '^\s*max\s*$') { $length = -1 }
    elseif ($args -match '^\s*(\d+)\s*,\s*(\d+)\s*$') { $precision = [int]$Matches[1]; $scale = [int]$Matches[2] }
    elseif ($args -match '^\s*(\d+)\s*$') { $length = [int]$Matches[1] }
    return [pscustomobject]@{
        Name      = $m.Groups[1].Value
        Type      = $m.Groups[2].Value.ToLowerInvariant()
        Length    = $length
        Precision = $precision
        Scale     = $scale
        Identity  = ($m.Groups[4].Value.Length -gt 0)
        Nullable  = ($m.Groups[5].Value -eq 'NULL')
    }
}

function Read-SyncSchema {
    param([string]$Text, [string[]]$Tables)
    $schema = @{}
    foreach ($table in $Tables) {
        $parts = $table.Split('.')
        $open = "EXEC('CREATE TABLE [{0}].[{1}] (" -f $parts[0], $parts[1]
        $at = $Text.IndexOf($open, [System.StringComparison]::Ordinal)
        if ($at -lt 0) { throw ('Table {0} was not found in the source schema.' -f $table) }
        $bodyStart = $Text.IndexOf("`n", $at) + 1
        $end = $Text.IndexOf("`n)')", $bodyStart, [System.StringComparison]::Ordinal)
        if ($end -lt 0) { throw ('Unterminated CREATE TABLE for {0}.' -f $table) }
        $columns = [System.Collections.Generic.List[object]]::new()
        $pk = @()
        foreach ($rawLine in $Text.Substring($bodyStart, $end - $bodyStart).Split("`n")) {
            $line = $rawLine.TrimEnd("`r").Trim().TrimEnd(',')
            if ($line.Length -eq 0) { continue }
            if ($line -match '^CONSTRAINT\s+\[[^\]]+\]\s+PRIMARY KEY\s*(?:CLUSTERED\s*)?\(([^)]*)\)') {
                $pk = @($Matches[1].Split(',') | ForEach-Object { $_.Trim().Trim('[', ']') })
                continue
            }
            if ($line -match '^(CONSTRAINT|PRIMARY|UNIQUE|FOREIGN|CHECK)\b') { continue }
            $col = ConvertTo-ColumnInfo -Line $line
            if ($null -eq $col) { throw ('Cannot parse column definition in {0}: {1}' -f $table, $line) }
            $columns.Add($col)
        }
        $schema[$table] = [pscustomobject]@{ Table = $table; Columns = $columns.ToArray(); PrimaryKey = $pk }
    }
    return $schema
}

function ConvertTo-NativeValue {
    param($Raw, $Column)
    if ($Raw.Kind -eq 'Z') { return $null }
    switch -Regex ($Column.Type) {
        '^(bit)$' { return [int]$Raw.Value }
        '^(tinyint|smallint|int|bigint)$' { return [long]::Parse($Raw.Value, [System.Globalization.CultureInfo]::InvariantCulture) }
        '^(decimal|numeric|money|smallmoney)$' { return [decimal]::Parse($Raw.Value, [System.Globalization.CultureInfo]::InvariantCulture) }
        '^(varbinary|binary|image)$' {
            if ($Raw.Kind -ne 'B') { throw ('Binary column {0} did not get a binary literal.' -f $Column.Name) }
            return , $Raw.Value
        }
        default { return $Raw.Value }
    }
}

function Read-SyncRows {
    param([string]$Text, [hashtable]$Schema)
    $rows = @{}
    foreach ($t in $Schema.Keys) { $rows[$t] = [System.Collections.Generic.List[object]]::new() }
    $from = 0
    $open = 'INSERT INTO ['
    while ($true) {
        $at = $Text.IndexOf($open, $from, [System.StringComparison]::Ordinal)
        if ($at -lt 0) { break }
        if ($at -gt 0 -and $Text[$at - 1] -ne "`n") { $from = $at + 1; continue }   # not a statement start
        $sep = $Text.IndexOf('] (', $at, [System.StringComparison]::Ordinal)
        $head = $Text.Substring($at + $open.Length, $sep - $at - $open.Length)       # schema].[table
        $table = $head.Replace('].[', '.')
        $colsEnd = $Text.IndexOf(') VALUES (', $sep, [System.StringComparison]::Ordinal)
        if ($colsEnd -lt 0) { $from = $at + 1; continue }
        $valuesStart = $colsEnd + ') VALUES ('.Length
        if (-not $Schema.ContainsKey($table)) {
            $from = (Find-ValuesEnd -Text $Text -Position $valuesStart) + 1
            continue
        }
        $names = @($Text.Substring($sep + 3, $colsEnd - $sep - 3).Split(',') | ForEach-Object { $_.Trim().Trim('[', ']') })
        $byName = @{}
        foreach ($c in $Schema[$table].Columns) { $byName[$c.Name] = $c }
        $row = [ordered]@{}
        $pos = $valuesStart
        for ($n = 0; $n -lt $names.Count; $n++) {
            $raw = Read-SqlValue -Text $Text -Position $pos
            $pos = $raw.Next
            while ($Text[$pos] -eq ' ') { $pos++ }
            if ($n -lt $names.Count - 1) {
                if ($Text[$pos] -ne ',') { throw ('Expected a comma in {0}.' -f $table) }
                $pos++
            }
            if (-not $byName.ContainsKey($names[$n])) { throw ('Column {0}.{1} is not in the schema.' -f $table, $names[$n]) }
            $row[$names[$n]] = ConvertTo-NativeValue -Raw $raw -Column $byName[$names[$n]]
        }
        if ($Text[$pos] -ne ')') { throw ('Unexpected extra values in {0}.' -f $table) }
        $rows[$table].Add($row)
        $from = $pos + 1
    }
    return $rows
}

# ---------------------------------------------------------------------------
# Source adapter: SQL Server (read only) [V] not tested against a real server
# ---------------------------------------------------------------------------

function Read-SqlServerSource {
    param([string]$Instance, [string]$DatabaseName, [string]$ClientPath, [string[]]$Tables, [switch]$TrustCertificate)
    $dll = $ClientPath
    if (Test-Path -LiteralPath $ClientPath -PathType Container) { $dll = Join-Path $ClientPath 'Microsoft.Data.SqlClient.dll' }
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw ('Microsoft.Data.SqlClient.dll was not found at: {0}' -f $dll) }
    Add-Type -Path $dll

    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Instance
    $builder['Initial Catalog'] = $DatabaseName
    $builder['Integrated Security'] = $true
    $builder['Application Intent'] = [Microsoft.Data.SqlClient.ApplicationIntent]::ReadOnly
    $builder['Application Name'] = 'Convert-ManagementDb'
    if ($TrustCertificate) { $builder['Trust Server Certificate'] = $true }

    $schema = @{}
    $rows = @{}
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $collation = ''
    try {
        $connection.Open()
        $collationCmd = $connection.CreateCommand()
        $collationCmd.CommandText = "SELECT CONVERT(nvarchar(128), DATABASEPROPERTYEX(DB_NAME(), 'Collation'));"
        $collation = [string]$collationCmd.ExecuteScalar()
        foreach ($table in $Tables) {
            $parts = $table.Split('.')
            $cmd = $connection.CreateCommand()
            $cmd.CommandText = @'
SELECT c.name, t.name AS type_name, c.max_length, c.precision, c.scale, c.is_nullable, c.is_identity
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(@full)
ORDER BY c.column_id;
'@
            [void]$cmd.Parameters.AddWithValue('@full', ('[{0}].[{1}]' -f $parts[0], $parts[1]))
            $columns = [System.Collections.Generic.List[object]]::new()
            $reader = $cmd.ExecuteReader()
            try {
                while ($reader.Read()) {
                    $typeName = ([string]$reader['type_name']).ToLowerInvariant()
                    $maxLength = [int]$reader['max_length']
                    $length = $maxLength
                    if ($typeName -in @('nvarchar', 'nchar') -and $maxLength -gt 0) { $length = $maxLength / 2 }
                    $columns.Add([pscustomobject]@{
                            Name = [string]$reader['name']; Type = $typeName; Length = [int]$length
                            Precision = [int]$reader['precision']; Scale = [int]$reader['scale']
                            Identity = [bool]$reader['is_identity']; Nullable = [bool]$reader['is_nullable']
                        })
                }
            }
            finally { $reader.Dispose() }
            if ($columns.Count -eq 0) { throw ('Table {0} was not found in the database.' -f $table) }

            $pkCmd = $connection.CreateCommand()
            $pkCmd.CommandText = @'
SELECT col.name
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id
WHERE i.is_primary_key = 1 AND i.object_id = OBJECT_ID(@full)
ORDER BY ic.key_ordinal;
'@
            [void]$pkCmd.Parameters.AddWithValue('@full', ('[{0}].[{1}]' -f $parts[0], $parts[1]))
            $pk = [System.Collections.Generic.List[string]]::new()
            $pkReader = $pkCmd.ExecuteReader()
            try { while ($pkReader.Read()) { $pk.Add([string]$pkReader['name']) } } finally { $pkReader.Dispose() }
            $schema[$table] = [pscustomobject]@{ Table = $table; Columns = $columns.ToArray(); PrimaryKey = $pk.ToArray() }

            $skip = @($script:ExcludedColumns[$table])
            $selectable = @($columns | Where-Object { $_.Type -notin @('timestamp', 'rowversion') -and $skip -notcontains $_.Name })
            $dataCmd = $connection.CreateCommand()
            $dataCmd.CommandTimeout = 300
            $dataCmd.CommandText = 'SELECT {0} FROM [{1}].[{2}];' -f (($selectable | ForEach-Object { '[' + $_.Name + ']' }) -join ', '), $parts[0], $parts[1]
            $list = [System.Collections.Generic.List[object]]::new()
            $dataReader = $dataCmd.ExecuteReader()
            try {
                while ($dataReader.Read()) {
                    $row = [ordered]@{}
                    for ($k = 0; $k -lt $selectable.Count; $k++) {
                        $v = $dataReader.GetValue($k)
                        # Explicit assignments: an `if` expression would unroll a byte[] value.
                        $row[$selectable[$k].Name] = $v
                        if ($v -is [System.DBNull]) { $row[$selectable[$k].Name] = $null }
                        elseif ($v -is [bool]) { $row[$selectable[$k].Name] = [int]$v }
                    }
                    $list.Add($row)
                }
            }
            finally { $dataReader.Dispose() }
            $rows[$table] = $list
        }
    }
    finally { $connection.Dispose() }
    return [pscustomobject]@{ Schema = $schema; Rows = $rows; Collation = $collation }
}

# ---------------------------------------------------------------------------
# Rules: exclusion, redaction, safety net
# ---------------------------------------------------------------------------

function Protect-RuleRow {
    # Replaces a literal secret in a sensitive template by a reference token. Returns $true when changed.
    param([System.Collections.IDictionary]$Row, [hashtable]$Spec)
    if (-not $Row.Contains('IsSensitive') -or [int]$Row['IsSensitive'] -ne 1) { return $false }
    $template = [string]$Row[$Spec.Template]
    if ([string]::IsNullOrEmpty($template)) { return $false }
    if ([regex]::IsMatch($template, $script:PlaceholderPattern)) { return $false }
    $ref = '{{secret:RULE:' + [string]$Row[$Spec.Id] + '}}'
    $m = [regex]::Match($template, '^(?i)([A-Za-z][A-Za-z0-9._-]*(?:password|secret|token|key)[A-Za-z0-9._-]*=)\S+$')
    if ($m.Success) { $Row[$Spec.Template] = $m.Groups[1].Value + $ref }
    else { $Row[$Spec.Template] = $ref }
    return $true
}

function Get-SecretPatternTable {
    $literal = '[^\s''",;\\{$%<)\[][^\s''",;\\{$%<)]{5,}'
    return [ordered]@{
        passwordLiteral   = '(?i)\b(password|pwd|passwd)\s*[=:]\s*' + $literal
        secretLiteral     = '(?i)\b(secret|apikey|api_key|token)\s*[=:]\s*' + $literal
        connectionUserAndSecret = '(?i)User ID\s*=\s*[^;]+;\s*Password\s*='
        privateKeyBlock   = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    }
}

function Test-NoSecretLiterals {
    # Safety net. Returns the hit list (table, column, pattern, count); never a value.
    param([hashtable]$Rows)
    $patterns = Get-SecretPatternTable
    $hits = [System.Collections.Generic.List[object]]::new()
    foreach ($table in $Rows.Keys) {
        $counts = @{}
        foreach ($row in $Rows[$table]) {
            foreach ($col in @($row.Keys)) {
                $v = $row[$col]
                if ($v -isnot [string] -or $v.Length -lt 8) { continue }
                # Placeholders and reference tokens ({{...}}) are not literals.
                $v = [regex]::Replace($v, '\{\{[^{}]*\}\}', '')
                foreach ($p in $patterns.Keys) {
                    $n = [regex]::Matches($v, $patterns[$p]).Count
                    if ($n -gt 0) { $k = $col + '|' + $p; $counts[$k] = [int]$counts[$k] + $n }
                }
            }
        }
        foreach ($k in $counts.Keys) {
            $parts = $k.Split('|')
            $hits.Add([pscustomobject]@{ Table = $table; Column = $parts[0]; Pattern = $parts[1]; Count = $counts[$k] })
        }
    }
    return , $hits.ToArray()
}

# ---------------------------------------------------------------------------
# SQLite: DDL, literals, sqlite3 execution
# ---------------------------------------------------------------------------

function Get-SqliteTableName { param([string]$Table) return $Table.Replace('.', '_') }

function Get-NonAsciiCodeFindings {
    # Only relevant with -CodeCollation NoCase. SQL Server Latin1_General_CI_AS folds all of Latin1;
    # SQLite NOCASE folds ASCII letters only. They agree while every *Code value is ASCII, so a
    # non-ASCII value in a NOCASE column is reported (counts only, never values).
    param([hashtable]$Schema, [hashtable]$Rows, [bool]$UseCodeCollation)
    $findings = [System.Collections.Generic.List[string]]::new()
    if (-not $UseCodeCollation) { return , $findings.ToArray() }
    foreach ($table in $script:CarriedTables.Keys) {
        foreach ($col in (Get-CarriedColumns -Table $table -TableSchema $Schema[$table])) {
            if ($col.Name -notmatch 'Code$' -or $col.Type -notin @('char', 'nchar', 'varchar', 'nvarchar', 'sysname')) { continue }
            $n = 0
            foreach ($row in $Rows[$table]) {
                if ($row.Contains($col.Name) -and $row[$col.Name] -is [string] -and [regex]::IsMatch($row[$col.Name], '[^\u0000-\u007F]')) { $n++ }
            }
            if ($n -gt 0) {
                $findings.Add(('{0}.{1}: {2} value(s) contain non-ASCII characters; SQLite NOCASE folds ASCII only, so case-insensitive matches may differ from SQL Server (Latin1_General_CI_AS).' -f (Get-SqliteTableName $table), $col.Name, $n))
            }
        }
    }
    return , $findings.ToArray()
}

function Get-CarriedColumns {
    param([string]$Table, $TableSchema)
    $skip = @($script:ExcludedColumns[$Table])
    return @($TableSchema.Columns | Where-Object { $_.Type -notin @('timestamp', 'rowversion') -and $skip -notcontains $_.Name })
}

function ConvertTo-SqliteColumnDefinition {
    param($Column, [bool]$UseCodeCollation, [bool]$IsSinglePrimaryKey)
    $q = '"' + $Column.Name + '"'
    $type = 'TEXT'
    $checks = [System.Collections.Generic.List[string]]::new()
    switch -Regex ($Column.Type) {
        '^bit$' { $type = 'INTEGER'; $checks.Add("$q IN (0, 1)") }
        '^(tinyint|smallint|int|bigint)$' { $type = 'INTEGER' }
        '^(varbinary|binary|image)$' { $type = 'BLOB' }
        '^uniqueidentifier$' { $checks.Add("length($q) = 36") }
        '^(char|nchar|varchar|nvarchar)$' { if ($Column.Length -gt 0) { $checks.Add("length($q) <= $($Column.Length)") } }
        '^sysname$' { $checks.Add("length($q) <= 128") }
    }
    $def = "$q $type"
    if (-not $Column.Nullable -or $IsSinglePrimaryKey) { $def += ' NOT NULL' }
    if ($type -eq 'TEXT' -and $UseCodeCollation -and $Column.Name -match 'Code$') { $def += ' COLLATE NOCASE' }
    foreach ($c in $checks) { $def += " CHECK ($c)" }
    return $def
}

function ConvertTo-SqliteCreateTable {
    param([string]$Table, $TableSchema, [bool]$UseCodeCollation)
    $cols = Get-CarriedColumns -Table $Table -TableSchema $TableSchema
    $pk = @($TableSchema.PrimaryKey | Where-Object { $cols.Name -contains $_ })
    $defs = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cols) {
        $defs.Add('  ' + (ConvertTo-SqliteColumnDefinition -Column $c -UseCodeCollation $UseCodeCollation -IsSinglePrimaryKey ($pk.Count -eq 1 -and $pk[0] -eq $c.Name)))
    }
    if ($pk.Count -gt 0) { $defs.Add('  PRIMARY KEY (' + (($pk | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ')') }
    return ('CREATE TABLE "{0}" (' -f (Get-SqliteTableName $Table)) + "`n" + ($defs -join ",`n") + "`n) STRICT;"
}

function ConvertTo-SqliteLiteral {
    param($Value, $Column)
    if ($null -eq $Value) { return 'NULL' }
    $type = $Column.Type
    if ($type -eq 'bit' -or $type -match '^(tinyint|smallint|int|bigint)$') {
        return ([long]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($type -match '^(varbinary|binary|image)$' -and $Value -isnot [byte[]]) {
        throw ('Binary column {0} did not receive bytes (got {1}).' -f $Column.Name, $Value.GetType().Name)
    }
    if ($Value -is [byte[]]) { return "X'" + [Convert]::ToHexString($Value) + "'" }
    if ($Value -is [decimal]) { return "'" + $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) + "'" }
    if ($Value -is [datetime]) { return "'" + $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture) + "'" }
    if ($Value -is [guid]) { return "'" + $Value.ToString('D').ToLowerInvariant() + "'" }
    $s = [string]$Value
    switch -Regex ($type) {
        '^(datetime2|datetime|smalldatetime)$' { $s = $s.Replace(' ', 'T') }
        '^uniqueidentifier$' { $s = $s.ToLowerInvariant() }
        '^(char|nchar)$' { $s = $s.TrimEnd(' ') }
    }
    # The sqlite3 shell removes the CR of every CRLF it reads, even inside a quoted literal, and a
    # NUL cannot be written in one. Any text with a control character is therefore written as the
    # hex of its UTF-8 bytes and cast back to TEXT, so the stored value is byte-exact.
    if ([regex]::IsMatch($s, '[\u0000-\u001F\u007F]')) {
        $utf8Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($s)
        return "CAST(X'" + [Convert]::ToHexString($utf8Bytes) + "' AS TEXT)"
    }
    return "'" + $s.Replace("'", "''") + "'"
}

function Invoke-Sqlite3 {
    # Runs sqlite3 with an argument list and optional stdin file. Returns stdout. Throws on a non-zero exit or any stderr text.
    param([string]$Exe, [string[]]$Arguments, [string]$StdinFile)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    if ($StdinFile) {
        $stream = [System.IO.File]::OpenRead($StdinFile)
        try { $stream.CopyTo($proc.StandardInput.BaseStream) } finally { $stream.Dispose() }
    }
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    $out = $outTask.GetAwaiter().GetResult()
    $err = $errTask.GetAwaiter().GetResult()
    if ($proc.ExitCode -ne 0 -or $err.Trim().Length -gt 0) {
        $text = $err.Trim()
        if ($text.Length -gt 600) { $text = $text.Substring(0, 600) + ' ...' }
        throw ('sqlite3 failed (exit {0}): {1}' -f $proc.ExitCode, $text)
    }
    return $out
}

# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------

function Get-Sha256OfFile {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-CatalogFile {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][hashtable]$Schema,
        [Parameter(Mandatory)][hashtable]$Rows,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$SourceKind,
        [string]$SourceRef,
        [bool]$UseCodeCollation
    )
    $final = Join-Path $Folder ('catalog-{0}.db' -f $Code)
    $temp = $final + '.tmp'
    $scriptFile = Join-Path $Folder ('catalog-{0}.build.sql' -f $Code)
    foreach ($f in @($temp, $scriptFile)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.IO.StreamWriter]::new($scriptFile, $false, $utf8)
    $expected = [ordered]@{}
    try {
        $writer.Write("PRAGMA foreign_keys = OFF;`nBEGIN;`n")
        $writer.Write("CREATE TABLE catalog_meta (`n  meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1),`n  schema_version INTEGER NOT NULL,`n  server_code TEXT NOT NULL,`n  source_kind TEXT NOT NULL,`n  source_reference TEXT NOT NULL,`n  built_at_utc TEXT NOT NULL,`n  cut_rule_version INTEGER NOT NULL`n) STRICT;`n")
        $built = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $writer.Write(("INSERT INTO catalog_meta VALUES (1, {0}, '{1}', '{2}', '{3}', '{4}', {5});`n" -f $script:SchemaVersion, $Code.Replace("'", "''"), $SourceKind, $SourceRef.Replace("'", "''"), $built, $script:CutRuleVersion))
        foreach ($table in $script:CarriedTables.Keys) {
            $ts = $Schema[$table]
            $writer.Write((ConvertTo-SqliteCreateTable -Table $table -TableSchema $ts -UseCodeCollation $UseCodeCollation) + "`n")
            $cols = Get-CarriedColumns -Table $table -TableSchema $ts
            $tname = Get-SqliteTableName $table
            $names = ($cols | ForEach-Object { '"' + $_.Name + '"' }) -join ', '
            $count = 0
            foreach ($row in $Rows[$table]) {
                $vals = foreach ($c in $cols) {
                    # No `if` expression here: it would unroll a byte[] into an object[].
                    $v = $null
                    if ($row.Contains($c.Name)) { $v = $row[$c.Name] }
                    ConvertTo-SqliteLiteral -Value $v -Column $c
                }
                $writer.Write(('INSERT INTO "{0}" ({1}) VALUES ({2});' -f $tname, $names, ($vals -join ', ')) + "`n")
                $count++
            }
            $expected[$tname] = $count
        }
        $writer.Write("COMMIT;`nPRAGMA user_version = $($script:SchemaVersion);`n")
    }
    finally { $writer.Dispose() }

    try {
        [void](Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($temp) -StdinFile $scriptFile)
        $integrity = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($temp, 'PRAGMA integrity_check;')).Trim()
        if ($integrity -ne 'ok') { throw ('integrity_check failed: {0}' -f $integrity) }
        $fk = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($temp, 'PRAGMA foreign_key_check;')).Trim()
        if ($fk.Length -gt 0) { throw 'foreign_key_check reported violations.' }
        [void](Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($temp, 'VACUUM;'))

        $countSql = (($expected.Keys | ForEach-Object { "SELECT '{0}', count(*) FROM `"{0}`";" -f $_ }) -join ' ')
        $actual = @{}
        foreach ($line in ((Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($temp, $countSql)) -split "`n")) {
            if ($line.Trim().Length -eq 0) { continue }
            $p = $line.Trim().Split('|')
            $actual[$p[0]] = [int]$p[1]
        }
        $tables = [System.Collections.Generic.List[object]]::new()
        foreach ($k in $expected.Keys) {
            if ($actual[$k] -ne $expected[$k]) { throw ('Row count mismatch in {0}: expected {1}, found {2}.' -f $k, $expected[$k], $actual[$k]) }
            $tables.Add([ordered]@{ table = $k; sourceRows = $expected[$k]; destinationRows = $actual[$k] })
        }
        if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }
        Move-Item -LiteralPath $temp -Destination $final
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $scriptFile) { Remove-Item -LiteralPath $scriptFile -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ File = $final; Tables = $tables.ToArray(); BuiltAtUtc = $built }
}

function Invoke-NewMachineConversion {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][hashtable]$SourceInfo,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Services,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$SourceRef,
        [bool]$UseCodeCollation = $false
    )
    if ($Code -notmatch '^[A-Za-z0-9_-]{1,30}$') { throw 'ServerCode must be 1 to 30 characters from A-Z, a-z, 0-9, underscore and hyphen.' }
    if ($Machine.Length -lt 1 -or $Machine.Length -gt 128) { throw 'MachineName must be 1 to 128 characters.' }
    if ($Services.Length -lt 1 -or $BackupRoot.Length -lt 1) { throw 'ServicesRoot and ConfigBackupRoot are required.' }
    if (-not (Test-Path -LiteralPath $Sqlite3 -PathType Leaf)) { throw ('sqlite3 was not found at: {0}' -f $Sqlite3) }

    foreach ($existing in $Source.Rows['dbo.ManagedServer']) {
        if ([string]$existing['ServerCode'] -ieq $Code) { throw ('ServerCode {0} already exists in the source. Use the cut mode (step B3), not -NewMachine.' -f $Code) }
    }

    # Work on copies so the source stays untouched.
    $rows = @{}
    $redacted = [System.Collections.Generic.List[string]]::new()
    foreach ($table in $script:CarriedTables.Keys) {
        $class = $script:CarriedTables[$table]
        $list = [System.Collections.Generic.List[object]]::new()
        if ($class -eq 'G') {
            foreach ($srcRow in $Source.Rows[$table]) {
                $row = [ordered]@{}
                foreach ($k in $srcRow.Keys) { $row[$k] = $srcRow[$k] }
                if ($script:RedactionTables.ContainsKey($table)) {
                    $spec = $script:RedactionTables[$table]
                    if (Protect-RuleRow -Row $row -Spec $spec) { $redacted.Add(('{0}:{1}' -f $table, $row[$spec.Id])) }
                }
                $list.Add($row)
            }
        }
        $rows[$table] = $list
    }
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture)
    $serverRow = [ordered]@{
        ServerCode = $Code; MachineName = $Machine; ServicesRoot = $Services; IsEnabled = 1
        CreatedAt = $now; ModifiedAt = $now; ConfigBackupRoot = $BackupRoot
    }
    $rows['dbo.ManagedServer'].Add($serverRow)

    $hits = Test-NoSecretLiterals -Rows $rows
    if ($hits.Count -gt 0) {
        $detail = ($hits | ForEach-Object { '{0}.{1} ({2} x {3})' -f $_.Table, $_.Column, $_.Pattern, $_.Count }) -join '; '
        throw ('Safety net: secret-like literals remain after redaction, nothing was written. Hits: {0}' -f $detail)
    }

    New-Item -ItemType Directory -Path $Folder -Force | Out-Null
    $catalog = New-CatalogFile -Code $Code -Schema $Source.Schema -Rows $rows -Folder $Folder -Sqlite3 $Sqlite3 -SourceKind 'conversion-tool' -SourceRef $SourceRef -UseCodeCollation $UseCodeCollation

    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($f in (Get-NonAsciiCodeFindings -Schema $Source.Schema -Rows $rows -UseCodeCollation $UseCodeCollation)) { $findings.Add($f) }
    foreach ($t in $script:CarriedTables.Keys) {
        if ($script:CarriedTables[$t] -ne 'G' -and $t -ne 'dbo.ManagedServer') {
            $findings.Add(('{0} is empty: a new machine has no rows to cut. Engines that need it stop with "policy missing" until the owner adds rows and seals the package.' -f (Get-SqliteTableName $t)))
        }
    }
    $excluded = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $script:ExcludedColumns.Keys) { foreach ($c in $script:ExcludedColumns[$t]) { $excluded.Add(('{0}.{1}' -f $t, $c)) } }

    $manifest = [ordered]@{
        contractVersion = '0.1-proposed'
        tool            = 'Convert-ManagementDb'
        toolVersion     = $script:ToolVersion
        mode            = 'new-machine'
        convertedAtUtc  = $catalog.BuiltAtUtc
        source          = $SourceInfo
        codeCollation   = $(if ($UseCodeCollation) { 'NOCASE' } else { 'BINARY' })
        sourceCollation = $(if ($SourceInfo.ContainsKey('collation')) { [string]$SourceInfo['collation'] } else { 'not available from an offline file; the owner states Latin1_General_CI_AS (2026-10-05) [V]' })
        catalogs        = @([ordered]@{
                serverCode       = $Code
                file             = (Split-Path -Leaf $catalog.File)
                sha256           = (Get-Sha256OfFile -Path $catalog.File)
                bytes            = (Get-Item -LiteralPath $catalog.File).Length
                schemaVersion    = $script:SchemaVersion
                cutRuleVersion   = $script:CutRuleVersion
                tables           = $catalog.Tables
                redactedRules    = $redacted.ToArray()
                redactedRuleCount = $redacted.Count
                excludedColumns  = $excluded.ToArray()
                findings         = $findings.ToArray()
            })
        excludedTableCount = 55
    }
    $json = ($manifest | ConvertTo-Json -Depth 10 -EscapeHandling EscapeNonAscii)
    $json = ($json -replace "`r`n", "`n") + "`n"
    $manifestPath = Join-Path $Folder 'conversion-manifest.json'
    [System.IO.File]::WriteAllBytes($manifestPath, [System.Text.UTF8Encoding]::new($false).GetBytes($json))
    return [pscustomobject]@{ Catalog = $catalog.File; Manifest = $manifestPath; Redacted = $redacted.Count }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $NewMachine) { throw 'Only -NewMachine is implemented in this version. The cut mode for existing machines is step B3.' }
    foreach ($required in @('ServerCode', 'MachineName', 'ServicesRoot', 'ConfigBackupRoot')) {
        if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $required -ValueOnly))) { throw ('-{0} is required with -NewMachine.' -f $required) }
    }
    $tables = @($script:CarriedTables.Keys)
    if ($PSCmdlet.ParameterSetName -eq 'Sync') {
        $resolved = (Resolve-Path -LiteralPath $SyncFile).Path
        $item = Get-Item -LiteralPath $resolved
        Write-Host ('Reading {0} ({1} bytes)...' -f $item.Name, $item.Length)
        $text = [System.IO.File]::ReadAllText($resolved, [System.Text.UTF8Encoding]::new($false))
        $schema = Read-SyncSchema -Text $text -Tables $tables
        $rows = Read-SyncRows -Text $text -Schema $schema
        $source = [pscustomobject]@{ Schema = $schema; Rows = $rows }
        $info = @{ kind = 'sync-file'; fileName = $item.Name; fileBytes = $item.Length; fileSha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    else {
        $source = Read-SqlServerSource -Instance $SqlInstance -DatabaseName $Database -ClientPath $SqlClientPath -Tables $tables -TrustCertificate:$TrustServerCertificate
        $info = @{ kind = 'sql-server'; instance = $SqlInstance; database = $Database; readOnly = $true; trustServerCertificate = [bool]$TrustServerCertificate; collation = $source.Collation }
    }
    $result = Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder $OutputFolder -Sqlite3 $Sqlite3Path -Code $ServerCode -Machine $MachineName -Services $ServicesRoot -BackupRoot $ConfigBackupRoot -SourceRef $SourceReference -UseCodeCollation ($CodeCollation -eq 'NoCase')
    Write-Host ('Catalog: {0}' -f $result.Catalog)
    Write-Host ('Manifest: {0}' -f $result.Manifest)
    Write-Host ('Redacted rule templates: {0}' -f $result.Redacted)
}
