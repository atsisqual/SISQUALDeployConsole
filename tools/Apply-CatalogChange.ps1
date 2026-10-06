#requires -Version 7.0
<#
.SYNOPSIS
    Applies a structured, reviewable change proposal to one SQLite catalog.

.DESCRIPTION
    C9 offline owner tool. The proposal contains data only, never SQL. The tool validates the
    current catalog with the existing Seal-Package catalog validator, binds the proposal to the
    exact catalog SHA-256 and ServerCode, resolves every table/column/primary key from SQLite
    metadata, edits a same-volume temporary copy, validates that copy, writes a baseline copy,
    rechecks the source hash and atomically replaces the catalog.

    It deliberately does NOT update package-manifest.json and does not sign anything. After a
    successful edit the package no longer matches its old manifest and must be processed by
    Seal-Package.ps1 with the baseline. Production catalog edits also require the approved second
    reader procedure; this tool does not invent an identity or approval store.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProposalPath,
    [Parameter(Mandatory)][string]$CatalogPath,
    [Parameter(Mandatory)][string]$Sqlite3Path,
    [string]$BaselinePath = '',
    [switch]$DryRun,
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:C9ShouldExecute = ($MyInvocation.InvocationName -ne '.')
$script:C9Cli = [ordered]@{
    ProposalPath = $ProposalPath
    CatalogPath = $CatalogPath
    Sqlite3Path = $Sqlite3Path
    BaselinePath = $BaselinePath
    DryRun = [bool]$DryRun
    Yes = [bool]$Yes
}

# Reuse the exact catalog safety validator and sqlite process wrapper already proven by B5.
# Dot-sourcing does not execute Seal-Package's CLI block.
. (Join-Path $PSScriptRoot 'Seal-Package.ps1') -PackageFolder 'unused' -Sqlite3Path 'unused' -Unsigned

$script:C9ToolVersion = '0.1.0'
$script:C9ContractVersion = '0.1-proposed'
$script:C9ForbiddenTables = @('catalog_meta', 'cfg_LinksPageDirectory')
$script:C9ForbiddenTablePatterns = @('sqlite_*', 'sec_ManagedCredential*')
$script:C9ForbiddenColumns = @(
    'IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken', 'ScriptText', 'ScriptSha256',
    'RowVersion', 'ManagementDatabaseName', 'SecretCipher'
)

function Get-C9Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileSha256Hex -Path $Path)
}

function ConvertFrom-C9JsonElement {
    param([Parameter(Mandatory)][System.Text.Json.JsonElement]$Element)
    switch ($Element.ValueKind) {
        ([System.Text.Json.JsonValueKind]::Object) {
            $result = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            foreach ($property in $Element.EnumerateObject()) {
                if ($result.ContainsKey($property.Name)) { throw ('JSON contains duplicate property "{0}".' -f $property.Name) }
                $result.Add($property.Name, (ConvertFrom-C9JsonElement -Element $property.Value))
            }
            return $result
        }
        ([System.Text.Json.JsonValueKind]::Array) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) { $items.Add((ConvertFrom-C9JsonElement -Element $item)) }
            return ,$items.ToArray()
        }
        ([System.Text.Json.JsonValueKind]::String) { return $Element.GetString() }
        ([System.Text.Json.JsonValueKind]::Number) {
            try { return [long]$Element.GetInt64() }
            catch { throw 'JSON numbers in a catalog-change proposal must be integers.' }
        }
        ([System.Text.Json.JsonValueKind]::True) { return $true }
        ([System.Text.Json.JsonValueKind]::False) { return $false }
        ([System.Text.Json.JsonValueKind]::Null) { return $null }
        default { throw ('Unsupported JSON value kind: {0}.' -f $Element.ValueKind) }
    }
}

function Read-C9Proposal {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('The proposal file was not found: {0}' -f $Path) }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    if ($bytes.Length -eq 0 -or $bytes.Length -gt 1048576) { throw 'The proposal must be between 1 byte and 1 MiB.' }
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try { $text = $utf8.GetString($bytes) }
    catch { throw 'The proposal is not valid UTF-8.' }
    if ($text.IndexOf([char]0) -ge 0) { throw 'The proposal contains a NUL character.' }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
    $options.MaxDepth = 16
    try { $doc = [System.Text.Json.JsonDocument]::Parse($text, $options) }
    catch { throw ('The proposal is not valid strict JSON: {0}' -f $_.Exception.Message) }
    try {
        if ($doc.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'The proposal root must be a JSON object.' }
        return (ConvertFrom-C9JsonElement -Element $doc.RootElement)
    }
    finally { $doc.Dispose() }
}

function Assert-C9ObjectShape {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Object,
        [Parameter(Mandatory)][string[]]$Required,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][string]$Context
    )
    foreach ($name in $Required) {
        if (-not $Object.ContainsKey($name)) { throw ('{0} is missing required member {1}.' -f $Context, $name) }
    }
    $allowedSet = [System.Collections.Generic.HashSet[string]]::new($Allowed, [System.StringComparer]::Ordinal)
    foreach ($name in $Object.Keys) {
        if (-not $allowedSet.Contains($name)) { throw ('{0} has unknown member {1}.' -f $Context, $name) }
    }
}

function Test-C9AsciiPrintable {
    param([string]$Text, [int]$MaxLength)
    if ($null -eq $Text -or $Text.Length -gt $MaxLength) { return $false }
    foreach ($ch in $Text.ToCharArray()) { if ([int]$ch -lt 32 -or [int]$ch -gt 126) { return $false } }
    return $true
}

function Test-C9SameNames {
    param([System.Collections.IDictionary]$Left, [System.Collections.IDictionary]$Right)
    if ($Left.Count -ne $Right.Count) { return $false }
    foreach ($name in $Left.Keys) {
        $found = $false
        foreach ($candidate in $Right.Keys) { if ([string]$candidate -ceq [string]$name) { $found = $true; break } }
        if (-not $found) { return $false }
    }
    return $true
}

function Test-C9ValuesEqual {
    param($Left, $Right)
    if ($null -eq $Left -or $null -eq $Right) { return ($null -eq $Left -and $null -eq $Right) }
    if ($Left.GetType() -ne $Right.GetType()) { return $false }
    if ($Left -is [string]) { return ([string]$Left -ceq [string]$Right) }
    return ($Left -eq $Right)
}

function Get-C9SqliteSchema {
    param([Parameter(Mandatory)][string]$Sqlite3, [Parameter(Mandatory)][string]$CatalogDb)
    $tables = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $tableJson = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', '-json', $CatalogDb, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
    $tableRows = @()
    if (-not [string]::IsNullOrWhiteSpace($tableJson)) { $tableRows = @($tableJson | ConvertFrom-Json -DateKind String) }
    foreach ($tableRow in $tableRows) {
        $tableName = [string]$tableRow.name
        $escaped = $tableName.Replace("'", "''")
        $columnJson = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', '-json', $CatalogDb, ("SELECT name,type,`"notnull`" AS not_null,pk FROM pragma_table_info('{0}') ORDER BY cid;" -f $escaped))
        $columnRows = @()
        if (-not [string]::IsNullOrWhiteSpace($columnJson)) { $columnRows = @($columnJson | ConvertFrom-Json -DateKind String) }
        $columns = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $pkByOrder = [System.Collections.Generic.SortedDictionary[int, string]]::new()
        foreach ($columnRow in $columnRows) {
            $columnName = [string]$columnRow.name
            $info = [pscustomobject]@{
                Name = $columnName
                Type = ([string]$columnRow.type).ToUpperInvariant()
                NotNull = ([int]$columnRow.not_null -eq 1)
                PkOrder = [int]$columnRow.pk
            }
            $columns.Add($columnName, $info)
            if ($info.PkOrder -gt 0) { $pkByOrder.Add($info.PkOrder, $columnName) }
        }
        $tables.Add($tableName, [pscustomobject]@{ Name = $tableName; Columns = $columns; PrimaryKey = @($pkByOrder.Values) })
    }
    return $tables
}

function Test-C9ForbiddenTable {
    param([string]$Table)
    if (@($script:C9ForbiddenTables | Where-Object { $_ -ceq $Table }).Count -gt 0) { return $true }
    foreach ($pattern in $script:C9ForbiddenTablePatterns) { if ($Table -like $pattern) { return $true } }
    return $false
}

function Test-C9ForbiddenColumn {
    param([string]$Column)
    return (@($script:C9ForbiddenColumns | Where-Object { $_ -ceq $Column }).Count -gt 0)
}

function Get-C9Affinity {
    param([string]$DeclaredType)
    $type = $DeclaredType.ToUpperInvariant()
    if ($type -match 'INT') { return 'INTEGER' }
    if ($type -match 'CHAR|CLOB|TEXT') { return 'TEXT' }
    if ($type -match 'BLOB' -or $type.Length -eq 0) { return 'BLOB' }
    if ($type -match 'REAL|FLOA|DOUB') { return 'REAL' }
    return 'NUMERIC'
}

function Assert-C9CellValue {
    param($Value, $Column, [string]$Context)
    if ($null -eq $Value) {
        if ($Column.NotNull -or $Column.PkOrder -gt 0) { throw ('{0}: column {1} cannot be NULL.' -f $Context, $Column.Name) }
        return
    }
    $affinity = Get-C9Affinity -DeclaredType $Column.Type
    switch ($affinity) {
        'TEXT' {
            if ($Value -isnot [string]) { throw ('{0}: column {1} requires a JSON string or null.' -f $Context, $Column.Name) }
        }
        'INTEGER' {
            if ($Value -isnot [long] -and $Value -isnot [bool]) { throw ('{0}: column {1} requires a JSON integer/boolean or null.' -f $Context, $Column.Name) }
        }
        default { throw ('{0}: C9 V1 refuses edits of {1} affinity column {2}.' -f $Context, $affinity, $Column.Name) }
    }
}

function ConvertTo-C9SqlIdentifier {
    param([Parameter(Mandatory)][string]$Name)
    return '"' + $Name.Replace('"', '""') + '"'
}

function ConvertTo-C9SqlLiteral {
    param($Value)
    if ($null -eq $Value) { return 'NULL' }
    if ($Value -is [bool]) { return $(if ($Value) { '1' } else { '0' }) }
    if ($Value -is [long]) { return $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [string]) {
        $hex = [Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes([string]$Value))
        return ("CAST(X'{0}' AS TEXT)" -f $hex)
    }
    throw ('Unsupported proposal value type {0}.' -f $Value.GetType().FullName)
}

function ConvertTo-C9PredicateTerm {
    param([string]$Column, $Value)
    $id = ConvertTo-C9SqlIdentifier -Name $Column
    if ($null -eq $Value) { return ($id + ' IS NULL') }
    return ($id + ' = ' + (ConvertTo-C9SqlLiteral -Value $Value))
}

function Assert-C9RowObject {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Values,
        $TableSchema,
        [Parameter(Mandatory)][string]$Context,
        [switch]$DisallowPrimaryKey
    )
    foreach ($name in $Values.Keys) {
        if (-not $TableSchema.Columns.ContainsKey($name)) { throw ('{0}: column {1} does not exist.' -f $Context, $name) }
        if (Test-C9ForbiddenColumn -Column $name) { throw ('{0}: column {1} is forbidden.' -f $Context, $name) }
        $column = $TableSchema.Columns[$name]
        if ($DisallowPrimaryKey -and $column.PkOrder -gt 0) { throw ('{0}: primary-key column {1} cannot be changed or repeated.' -f $Context, $name) }
        Assert-C9CellValue -Value $Values[$name] -Column $column -Context $Context
    }
}

function Assert-C9Key {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Key,
        $TableSchema,
        [Parameter(Mandatory)][string]$Context
    )
    $pk = @($TableSchema.PrimaryKey)
    if ($pk.Count -eq 0) { throw ('{0}: table {1} has no primary key and cannot be changed by C9.' -f $Context, $TableSchema.Name) }
    if ($Key.Count -ne $pk.Count) { throw ('{0}: key must name exactly the primary-key columns: {1}.' -f $Context, ($pk -join ', ')) }
    foreach ($name in $pk) {
        if (-not $Key.ContainsKey($name)) { throw ('{0}: key must name exactly the primary-key columns: {1}.' -f $Context, ($pk -join ', ')) }
        Assert-C9CellValue -Value $Key[$name] -Column $TableSchema.Columns[$name] -Context $Context
        if ($null -eq $Key[$name]) { throw ('{0}: primary-key value {1} cannot be NULL.' -f $Context, $name) }
    }
    foreach ($name in $Key.Keys) { if (-not (@($pk | Where-Object { $_ -ceq $name }).Count -eq 1)) { throw ('{0}: key contains non-primary-key column {1}.' -f $Context, $name) } }
}

function Assert-C9Proposal {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.Dictionary[string, object]]$Proposal,
        [Parameter(Mandatory)]$Schema,
        [Parameter(Mandatory)][string]$ExpectedServerCode,
        [Parameter(Mandatory)][string]$ExpectedHash
    )
    Assert-C9ObjectShape -Object $Proposal -Required @('contractVersion','changeId','catalogServerCode','baseCatalogSha256','note','operations') -Allowed @('contractVersion','changeId','catalogServerCode','baseCatalogSha256','note','operations') -Context 'proposal'
    if ([string]$Proposal['contractVersion'] -cne $script:C9ContractVersion) { throw ('Unsupported catalog-change contractVersion: {0}.' -f $Proposal['contractVersion']) }
    if ([string]$Proposal['changeId'] -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'changeId must be a lowercase GUID.' }
    if ([string]$Proposal['catalogServerCode'] -notmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'catalogServerCode has an invalid shape.' }
    if ([string]$Proposal['catalogServerCode'] -cne $ExpectedServerCode) { throw 'catalogServerCode does not match catalog_meta.server_code exactly.' }
    if ([string]$Proposal['baseCatalogSha256'] -notmatch '^[0-9a-f]{64}$') { throw 'baseCatalogSha256 must be 64 lowercase hexadecimal characters.' }
    if ([string]$Proposal['baseCatalogSha256'] -cne $ExpectedHash) { throw 'The proposal is stale: baseCatalogSha256 does not match the catalog.' }
    if (-not (Test-C9AsciiPrintable -Text ([string]$Proposal['note']) -MaxLength 200)) { throw 'note must be printable ASCII of at most 200 characters.' }
    $operations = @($Proposal['operations'])
    if ($operations.Count -lt 1 -or $operations.Count -gt 500) { throw 'operations must contain between 1 and 500 entries.' }

    for ($i = 0; $i -lt $operations.Count; $i++) {
        $operation = $operations[$i]
        if ($operation -isnot [System.Collections.Generic.Dictionary[string, object]]) { throw ('operation[{0}] must be an object.' -f $i) }
        $ctx = 'operation[{0}]' -f $i
        Assert-C9ObjectShape -Object $operation -Required @('kind','table','key') -Allowed @('kind','table','key','expected','values') -Context $ctx
        $kind = [string]$operation['kind']
        if ($kind -notin @('INSERT','UPDATE','DELETE')) { throw ('{0}: kind must be INSERT, UPDATE or DELETE.' -f $ctx) }
        $table = [string]$operation['table']
        if (-not $Schema.ContainsKey($table)) { throw ('{0}: table {1} does not exist.' -f $ctx, $table) }
        if (Test-C9ForbiddenTable -Table $table) { throw ('{0}: table {1} is not editable by C9.' -f $ctx, $table) }
        $tableSchema = $Schema[$table]
        if ($operation['key'] -isnot [System.Collections.Generic.Dictionary[string, object]]) { throw ('{0}.key must be an object.' -f $ctx) }
        Assert-C9Key -Key $operation['key'] -TableSchema $tableSchema -Context $ctx

        if ($kind -ceq 'INSERT') {
            if ($operation.ContainsKey('expected')) { throw ('{0}: INSERT must not contain expected.' -f $ctx) }
            if (-not $operation.ContainsKey('values') -or $operation['values'] -isnot [System.Collections.Generic.Dictionary[string, object]] -or $operation['values'].Count -eq 0) { throw ('{0}: INSERT requires a non-empty values object.' -f $ctx) }
            Assert-C9RowObject -Values $operation['values'] -TableSchema $tableSchema -Context $ctx -DisallowPrimaryKey
        }
        elseif ($kind -ceq 'UPDATE') {
            if (-not $operation.ContainsKey('expected') -or $operation['expected'] -isnot [System.Collections.Generic.Dictionary[string, object]] -or $operation['expected'].Count -eq 0) { throw ('{0}: UPDATE requires a non-empty expected object.' -f $ctx) }
            if (-not $operation.ContainsKey('values') -or $operation['values'] -isnot [System.Collections.Generic.Dictionary[string, object]] -or $operation['values'].Count -eq 0) { throw ('{0}: UPDATE requires a non-empty values object.' -f $ctx) }
            Assert-C9RowObject -Values $operation['expected'] -TableSchema $tableSchema -Context $ctx -DisallowPrimaryKey
            Assert-C9RowObject -Values $operation['values'] -TableSchema $tableSchema -Context $ctx -DisallowPrimaryKey
            if (-not (Test-C9SameNames -Left $operation['expected'] -Right $operation['values'])) { throw ('{0}: UPDATE expected and values must name the same columns.' -f $ctx) }
            $diff = 0
            foreach ($name in $operation['values'].Keys) { if (-not (Test-C9ValuesEqual -Left $operation['expected'][$name] -Right $operation['values'][$name])) { $diff++ } }
            if ($diff -eq 0) { throw ('{0}: UPDATE is a no-op.' -f $ctx) }
        }
        else {
            if ($operation.ContainsKey('values')) { throw ('{0}: DELETE must not contain values.' -f $ctx) }
            if (-not $operation.ContainsKey('expected') -or $operation['expected'] -isnot [System.Collections.Generic.Dictionary[string, object]] -or $operation['expected'].Count -eq 0) { throw ('{0}: DELETE requires a non-empty expected object.' -f $ctx) }
            Assert-C9RowObject -Values $operation['expected'] -TableSchema $tableSchema -Context $ctx -DisallowPrimaryKey
        }
    }
}

function ConvertTo-C9OperationSql {
    param([Parameter(Mandatory)]$Operation, $TableSchema, [int]$Index)
    $kind = [string]$Operation['kind']
    $tableId = ConvertTo-C9SqlIdentifier -Name ([string]$Operation['table'])
    $key = $Operation['key']
    $whereParts = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($TableSchema.PrimaryKey)) { $whereParts.Add((ConvertTo-C9PredicateTerm -Column $name -Value $key[$name])) }

    if ($kind -ceq 'INSERT') {
        $names = [System.Collections.Generic.List[string]]::new()
        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($name in @($TableSchema.PrimaryKey)) { $names.Add((ConvertTo-C9SqlIdentifier $name)); $values.Add((ConvertTo-C9SqlLiteral $key[$name])) }
        foreach ($name in $Operation['values'].Keys) { $names.Add((ConvertTo-C9SqlIdentifier $name)); $values.Add((ConvertTo-C9SqlLiteral $Operation['values'][$name])) }
        return ('INSERT INTO {0} ({1}) VALUES ({2});' -f $tableId, ($names -join ', '), ($values -join ', '))
    }

    foreach ($name in $Operation['expected'].Keys) { $whereParts.Add((ConvertTo-C9PredicateTerm -Column $name -Value $Operation['expected'][$name])) }
    $where = $whereParts -join ' AND '
    if ($kind -ceq 'UPDATE') {
        $sets = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $Operation['values'].Keys) { $sets.Add(('{0} = {1}' -f (ConvertTo-C9SqlIdentifier $name), (ConvertTo-C9SqlLiteral $Operation['values'][$name]))) }
        return ('UPDATE {0} SET {1} WHERE {2};' -f $tableId, ($sets -join ', '), $where)
    }
    return ('DELETE FROM {0} WHERE {1};' -f $tableId, $where)
}

function Invoke-C9SqliteScript {
    param([Parameter(Mandatory)][string]$Sqlite3, [Parameter(Mandatory)][string]$CatalogDb, [Parameter(Mandatory)][string]$Script)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Sqlite3)
    $psi.ArgumentList.Add($CatalogDb)
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.StandardInput.Write($Script)
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    $out = $outTask.GetAwaiter().GetResult()
    $err = $errTask.GetAwaiter().GetResult()
    if ($proc.ExitCode -ne 0 -or $err.Trim().Length -gt 0) {
        $safe = $err.Trim()
        if ($safe.Length -gt 400) { $safe = $safe.Substring(0, 400) + ' ...' }
        throw ('sqlite3 rejected the staged catalog change (exit {0}): {1}' -f $proc.ExitCode, $safe)
    }
    return $out
}

function Get-C9Summary {
    param([Parameter(Mandatory)]$Proposal)
    $counts = [ordered]@{ INSERT = 0; UPDATE = 0; DELETE = 0 }
    $tables = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($op in @($Proposal['operations'])) { $counts[[string]$op['kind']]++; [void]$tables.Add([string]$op['table']) }
    [string[]]$tableNames = @($tables)
    [Array]::Sort($tableNames, [System.StringComparer]::Ordinal)
    return [pscustomobject]@{ Counts = $counts; Tables = $tableNames }
}

function Invoke-CatalogChange {
    param(
        [Parameter(Mandatory)][string]$Proposal,
        [Parameter(Mandatory)][string]$Catalog,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string]$Baseline = '',
        [bool]$Preview = $false,
        [bool]$Confirmed = $false
    )
    if (-not (Test-Path -LiteralPath $Sqlite3 -PathType Leaf)) { throw ('sqlite3 was not found at: {0}' -f $Sqlite3) }
    if (-not (Test-Path -LiteralPath $Catalog -PathType Leaf)) { throw ('The catalog was not found: {0}' -f $Catalog) }
    $catalogFull = (Resolve-Path -LiteralPath $Catalog).Path
    $sqliteFull = (Resolve-Path -LiteralPath $Sqlite3).Path

    $initialCheck = Test-CatalogFile -Sqlite3 $sqliteFull -Db $catalogFull
    if ($initialCheck.Problems.Count -gt 0) { throw ("The current catalog is not safe to edit:`n  " + ($initialCheck.Problems -join "`n  ")) }
    $serverCode = [string]$initialCheck.Meta.ServerCode
    $beforeHash = Get-C9Sha256 -Path $catalogFull
    $proposalObject = Read-C9Proposal -Path $Proposal
    $schema = Get-C9SqliteSchema -Sqlite3 $sqliteFull -CatalogDb $catalogFull
    Assert-C9Proposal -Proposal $proposalObject -Schema $schema -ExpectedServerCode $serverCode -ExpectedHash $beforeHash
    $summary = Get-C9Summary -Proposal $proposalObject

    Write-Host ('Catalog change {0} for {1}' -f $proposalObject['changeId'], $serverCode)
    Write-Host ('Base SHA-256: {0}' -f $beforeHash)
    Write-Host ('Operations: {0} insert, {1} update, {2} delete across {3} table(s).' -f $summary.Counts.INSERT, $summary.Counts.UPDATE, $summary.Counts.DELETE, $summary.Tables.Count)
    foreach ($table in $summary.Tables) { Write-Host ('  table: {0}' -f $table) }

    if ($Preview) {
        Write-Host 'Dry run: proposal and catalog validated; nothing was written.'
        return [pscustomobject]@{
            Applied = $false; ChangeId = [string]$proposalObject['changeId']; ServerCode = $serverCode
            Operations = @($proposalObject['operations']).Count; Tables = $summary.Tables; BeforeSha256 = $beforeHash
            AfterSha256 = $beforeHash; BaselinePath = ''; RequiresReseal = $false
        }
    }

    if ([string]::IsNullOrWhiteSpace($Baseline)) { throw '-BaselinePath is required when applying a catalog change.' }
    $baselineFull = [System.IO.Path]::GetFullPath($Baseline)
    if ([string]::Equals($baselineFull, $catalogFull, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'BaselinePath must be different from CatalogPath.' }
    if (Test-Path -LiteralPath $baselineFull) { throw ('BaselinePath already exists and will not be overwritten: {0}' -f $baselineFull) }
    $baselineParent = [System.IO.Path]::GetDirectoryName($baselineFull)
    if ([string]::IsNullOrWhiteSpace($baselineParent) -or -not (Test-Path -LiteralPath $baselineParent -PathType Container)) { throw 'The BaselinePath parent folder must already exist.' }

    if (-not $Confirmed) {
        if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { throw 'Confirmation is needed. Run in a console or pass -Yes.' }
        $answer = Read-Host 'Type APPLY to replace the catalog (it must be resealed afterwards)'
        if ($answer -cne 'APPLY') { throw 'Not confirmed. Nothing was written.' }
    }

    $catalogDir = [System.IO.Path]::GetDirectoryName($catalogFull)
    $workId = [guid]::NewGuid().ToString('N')
    $staged = Join-Path $catalogDir ('.c9-' + $workId + '.tmp')
    $rollback = Join-Path $catalogDir ('.c9-' + $workId + '.rollback')
    $baselineCreated = $false
    $replaced = $false
    try {
        [System.IO.File]::Copy($catalogFull, $staged, $false)
        $scriptLines = [System.Collections.Generic.List[string]]::new()
        $scriptLines.Add('.bail on')
        $scriptLines.Add('PRAGMA foreign_keys = ON;')
        $scriptLines.Add('BEGIN IMMEDIATE;')
        $ops = @($proposalObject['operations'])
        for ($i = 0; $i -lt $ops.Count; $i++) {
            $op = $ops[$i]
            $sql = ConvertTo-C9OperationSql -Operation $op -TableSchema $schema[[string]$op['table']] -Index $i
            $scriptLines.Add($sql)
            $scriptLines.Add(("SELECT '__C9_OP_{0:D4}__|' || changes();" -f $i))
        }
        $scriptLines.Add('COMMIT;')
        $output = Invoke-C9SqliteScript -Sqlite3 $sqliteFull -CatalogDb $staged -Script (($scriptLines -join "`n") + "`n")
        for ($i = 0; $i -lt $ops.Count; $i++) {
            $marker = '__C9_OP_{0:D4}__|' -f $i
            $matches = @($output -split "`r?`n" | Where-Object { $_.StartsWith($marker, [System.StringComparison]::Ordinal) })
            if ($matches.Count -ne 1 -or $matches[0] -cne ($marker + '1')) { throw ('operation[{0}] did not affect exactly one row; the original catalog was not changed.' -f $i) }
        }

        $stagedCheck = Test-CatalogFile -Sqlite3 $sqliteFull -Db $staged -ExpectedServerCode $serverCode
        if ($stagedCheck.Problems.Count -gt 0) { throw ("The staged catalog is not safe:`n  " + ($stagedCheck.Problems -join "`n  ")) }
        $stagedHash = Get-C9Sha256 -Path $staged
        if ($stagedHash -ceq $beforeHash) { throw 'The proposal produced no byte change; the original catalog was not changed.' }
        if ((Get-C9Sha256 -Path $catalogFull) -cne $beforeHash) { throw 'The catalog changed after validation; the proposal is stale and was not applied.' }

        [System.IO.File]::Copy($catalogFull, $baselineFull, $false)
        $baselineCreated = $true
        if ((Get-C9Sha256 -Path $baselineFull) -cne $beforeHash) { throw 'The baseline copy does not match the validated source catalog.' }
        if ((Get-C9Sha256 -Path $catalogFull) -cne $beforeHash) { throw 'The catalog changed while the baseline was being created; it was not replaced.' }

        [System.IO.File]::Replace($staged, $catalogFull, $rollback, $true)
        $replaced = $true
        $afterHash = Get-C9Sha256 -Path $catalogFull
        if ($afterHash -cne $stagedHash) {
            [System.IO.File]::Copy($rollback, $catalogFull, $true)
            $replaced = $false
            throw 'The replaced catalog hash differs from the validated staged catalog; the original was restored.'
        }
        $afterCheck = Test-CatalogFile -Sqlite3 $sqliteFull -Db $catalogFull -ExpectedServerCode $serverCode
        if ($afterCheck.Problems.Count -gt 0) {
            [System.IO.File]::Copy($rollback, $catalogFull, $true)
            $replaced = $false
            throw 'Post-replacement validation failed; the original catalog was restored.'
        }
        Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue
        $replaced = $false
        Write-Host ('Applied. Baseline: {0}' -f $baselineFull)
        Write-Host 'RESEAL REQUIRED: package-manifest.json intentionally still describes the previous catalog.'
        return [pscustomobject]@{
            Applied = $true; ChangeId = [string]$proposalObject['changeId']; ServerCode = $serverCode
            Operations = $ops.Count; Tables = $summary.Tables; BeforeSha256 = $beforeHash
            AfterSha256 = $afterHash; BaselinePath = $baselineFull; RequiresReseal = $true
        }
    }
    catch {
        if ($replaced -and (Test-Path -LiteralPath $rollback -PathType Leaf)) {
            [System.IO.File]::Copy($rollback, $catalogFull, $true)
            $replaced = $false
        }
        if ($baselineCreated -and (Test-Path -LiteralPath $baselineFull -PathType Leaf)) { Remove-Item -LiteralPath $baselineFull -Force -ErrorAction SilentlyContinue }
        throw
    }
    finally {
        Remove-Item -LiteralPath $staged -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $rollback -Force -ErrorAction SilentlyContinue
    }
}

if ($script:C9ShouldExecute) {
    $r = Invoke-CatalogChange -Proposal $script:C9Cli.ProposalPath -Catalog $script:C9Cli.CatalogPath -Sqlite3 $script:C9Cli.Sqlite3Path -Baseline $script:C9Cli.BaselinePath -Preview $script:C9Cli.DryRun -Confirmed $script:C9Cli.Yes
    if ($r.Applied) { Write-Host ('Changed catalog SHA-256: {0}' -f $r.AfterSha256) }
}
