#requires -Version 7.0
<#
.SYNOPSIS
    Verifies the catalogs written by Convert-ManagementDb.ps1 against their source.

.DESCRIPTION
    Step B4 of docs/migration/catalog-conversion-plan.md (section 5.2). Read only: it reads the
    source (a ManagementSync.sql file, or SQL Server through Microsoft.Data.SqlClient) and opens
    the catalogs read-only with sqlite3. It prints counts, table names and primary keys of rows
    that differ; it never prints a cell value or a secret.

    Groups of checks (all of them run; the exit code is 1 when any check fails):
      manifest     conversion-manifest.json agrees with the files (SHA-256, size, meta, no stray catalog);
      sqlite       integrity, foreign keys, STRICT tables, schema version, exact table list, read-only;
      exclusions   no secret, script, rowversion or retired column, no table outside the whitelist;
      values       EVERY cell of every carried table equals the cell computed from the source
                   (counts, primary keys, null counts and values), except the redacted rule templates,
                   which must be a reference token;
      cut          cut mode: the expected owner of every row is recomputed here, each instance is in
                   exactly one catalog, and no catalog holds a row of another machine;
      global       the global tables have identical content in every catalog;
      secrets      no literal secret of the source appears anywhere in a catalog or in the manifest,
                   and no secret-like literal remains in any text cell;
      stored-hash  the SHA-256 columns stored by the old system still match the catalog content.

    The reader of the source is shared with the converter; the "values" group therefore does not
    rely on it alone: the "stored-hash" group re-computes hashes from the catalog content.
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

    [Parameter(ParameterSetName = 'Sql')]
    [switch]$TrustServerCertificate,

    [Parameter(Mandatory)]
    [string]$CatalogFolder,

    [Parameter(Mandatory)]
    [string]$Sqlite3Path,

    # Optional JSON report (counts and names only).
    [string]$ReportPath = '',

    # Extra values that must not appear anywhere (used by tests; never printed).
    [string[]]$ExtraNeedle = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-sourcing binds the converter's parameters into this scope, so keep our own values first.
$script:Cli = @{
    SyncFile = $SyncFile; SqlInstance = $SqlInstance; Database = $Database; SqlClientPath = $SqlClientPath
    Trust = [bool]$TrustServerCertificate; CatalogFolder = $CatalogFolder; Sqlite3Path = $Sqlite3Path
    ReportPath = $ReportPath; ExtraNeedle = @($ExtraNeedle); ParameterSet = $PSCmdlet.ParameterSetName
}
. (Join-Path $PSScriptRoot 'Convert-ManagementDb.ps1') -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$script:TestToolVersion = '0.1.0'
$script:Checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Group, [string]$Name, [bool]$Ok, [string]$Detail = '')
    if ($Detail.Length -gt 600) { $Detail = $Detail.Substring(0, 600) + ' ...' }
    $script:Checks.Add([ordered]@{ group = $Group; check = $Name; ok = $Ok; detail = $Detail })
    $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
    if ($Detail) { Write-Host ('{0}  [{1}] {2}: {3}' -f $tag, $Group, $Name, $Detail) } else { Write-Host ('{0}  [{1}] {2}' -f $tag, $Group, $Name) }
}

# ---------------------------------------------------------------------------
# Tokens: every cell is compared as "<sqlite type>:<hex of its bytes>", the form sqlite3 gives back
# ---------------------------------------------------------------------------

function ConvertTo-HexOfText { param([string]$Text) return [Convert]::ToHexString([System.Text.UTF8Encoding]::new($false).GetBytes($Text)) }

function Get-ExpectedToken {
    param($Value, $Column)
    if ($null -eq $Value) { return 'null:' }
    $type = $Column.Type
    if ($type -eq 'bit' -or $type -match '^(tinyint|smallint|int|bigint)$') {
        $text = ([long]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        return 'integer:' + [Convert]::ToHexString([System.Text.Encoding]::ASCII.GetBytes($text))
    }
    if ($type -match '^(varbinary|binary|image)$') {
        if ($Value -isnot [byte[]]) { return 'invalid:' }
        return 'blob:' + [Convert]::ToHexString($Value)
    }
    if ($Value -is [decimal]) { return 'text:' + (ConvertTo-HexOfText $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)) }
    if ($Value -is [datetime]) { return 'text:' + (ConvertTo-HexOfText $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffff', [System.Globalization.CultureInfo]::InvariantCulture)) }
    if ($Value -is [guid]) { return 'text:' + (ConvertTo-HexOfText $Value.ToString('D').ToLowerInvariant()) }
    $s = [string]$Value
    switch -Regex ($type) {
        '^(datetime2|datetime|smalldatetime)$' { $s = $s.Replace(' ', 'T') }
        '^uniqueidentifier$' { $s = $s.ToLowerInvariant() }
        '^(char|nchar)$' { $s = $s.TrimEnd(' ') }
    }
    return 'text:' + (ConvertTo-HexOfText $s)
}

function Format-KeyToken {
    # Primary-key values are identifiers (codes, numbers); they are the only values ever shown.
    param([string]$Token)
    if ($Token.StartsWith('text:')) { return (ConvertFrom-TokenText $Token) }
    if ($Token.StartsWith('integer:')) { return [System.Text.Encoding]::ASCII.GetString([Convert]::FromHexString($Token.Substring(8))) }
    return '<' + $Token.Split(':')[0] + '>'
}

function ConvertFrom-TokenText {
    param([string]$Token)
    if (-not $Token.StartsWith('text:')) { return $null }
    $hex = $Token.Substring(5)
    if ($hex.Length -eq 0) { return '' }
    return [System.Text.UTF8Encoding]::new($false).GetString([Convert]::FromHexString($hex))
}

# ---------------------------------------------------------------------------
# Reading catalogs (sqlite3, read-only)
# ---------------------------------------------------------------------------

function Get-CatalogColumns {
    param([string]$Sqlite3, [string]$Db)
    $out = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, "SELECT m.name || '|' || p.name FROM sqlite_master m, pragma_table_info(m.name) p WHERE m.type = 'table' ORDER BY m.name, p.cid;")
    $map = [ordered]@{}
    foreach ($line in ($out -split "`n")) {
        $l = $line.Trim()
        if ($l.Length -eq 0) { continue }
        $parts = $l.Split('|')
        if (-not $map.Contains($parts[0])) { $map[$parts[0]] = [System.Collections.Generic.List[string]]::new() }
        $map[$parts[0]].Add($parts[1])
    }
    return $map
}

function Read-CatalogRows {
    # One sqlite3 call per catalog. Returns table -> list of token arrays (one per row).
    param([string]$Sqlite3, [string]$Db, [System.Collections.IDictionary]$Plan)
    $sql = [System.Text.StringBuilder]::new()
    foreach ($t in $Plan.Keys) {
        $cols = @($Plan[$t])
        if ($cols.Count -eq 0) { continue }
        $expr = ($cols | ForEach-Object { "typeof(`"$_`") || ':' || hex(`"$_`")" }) -join " || '|' || "
        [void]$sql.Append("SELECT '##T##' || '$t';`nSELECT $expr FROM `"$t`";`n")
    }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $sql.ToString(), [System.Text.UTF8Encoding]::new($false))
        $out = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db) -StdinFile $tmp
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    $result = [ordered]@{}
    $current = $null
    foreach ($line in ($out -split "`n")) {
        $l = $line.TrimEnd("`r")
        if ($l.StartsWith('##T##')) { $current = $l.Substring(5); $result[$current] = [System.Collections.Generic.List[object]]::new(); continue }
        if ($null -eq $current -or $l.Length -eq 0) { continue }
        $result[$current].Add($l.Split('|'))
    }
    return $result
}

function Test-SqliteWriteRefused {
    param([string]$Sqlite3, [string]$Db)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Sqlite3)
    foreach ($a in @('-readonly', $Db, 'CREATE TABLE zz_write_probe (a);')) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $o = $proc.StandardOutput.ReadToEndAsync(); $e = $proc.StandardError.ReadToEndAsync()
    $proc.WaitForExit()
    $null = $o.GetAwaiter().GetResult()
    $err = $e.GetAwaiter().GetResult()
    return ($proc.ExitCode -ne 0 -and $err -match '(?i)readonly|read-only|read only')
}

# ---------------------------------------------------------------------------
# Expected content, recomputed from the source (not taken from the converter's output)
# ---------------------------------------------------------------------------

function Get-ExpectedOwners {
    # Independent re-implementation of the cut rules of plan section 2.2.
    param($Source)
    $serverByLower = @{}; $serverByMachine = @{}; $serverOfInstance = @{}
    foreach ($srv in $Source.Rows['dbo.ManagedServer']) {
        $serverByLower[([string]$srv['ServerCode']).ToLowerInvariant()] = [string]$srv['ServerCode']
        $serverByMachine[([string]$srv['MachineName']).ToLowerInvariant()] = [string]$srv['ServerCode']
    }
    foreach ($inst in $Source.Rows['dbo.ManagedInstance']) {
        $sk = ([string]$inst['ServerCode']).ToLowerInvariant()
        if ($serverByLower.ContainsKey($sk)) { $serverOfInstance[([string]$inst['InstanceCode']).ToLowerInvariant()] = $serverByLower[$sk] }
    }
    $owned = @{}
    $unplaced = @{}
    foreach ($table in $script:CutKeys.Keys) {
        if (-not $script:CarriedTables.Contains($table)) { continue }
        $kind = $script:CutKeys[$table][0]; $column = $script:CutKeys[$table][1]
        $owned[$table] = @{}
        $unplaced[$table] = 0
        foreach ($row in $Source.Rows[$table]) {
            $v = $null
            if ($row.Contains($column) -and $null -ne $row[$column]) { $v = ([string]$row[$column]).ToLowerInvariant() }
            $owner = $null
            if ($v) {
                if ($kind -eq 'Server' -and $serverByLower.ContainsKey($v)) { $owner = $serverByLower[$v] }
                elseif ($kind -eq 'Instance' -and $serverOfInstance.ContainsKey($v)) { $owner = $serverOfInstance[$v] }
                elseif ($kind -eq 'Machine' -and $serverByMachine.ContainsKey($v)) { $owner = $serverByMachine[$v] }
            }
            if ($null -eq $owner) { $unplaced[$table]++; continue }
            if (-not $owned[$table].ContainsKey($owner)) { $owned[$table][$owner] = [System.Collections.Generic.List[object]]::new() }
            $owned[$table][$owner].Add($row)
        }
    }
    return [pscustomobject]@{ Owned = $owned; Unplaced = $unplaced }
}

function Get-PrimaryKeyColumns {
    param($Schema, [string]$Table, $CarriedColumns)
    $names = @($CarriedColumns | ForEach-Object { $_.Name })
    return @($Schema[$Table].PrimaryKey | Where-Object { $names -contains $_ })
}

function Compare-TableRows {
    # Returns counts and the primary keys that differ. No cell value is returned.
    param([string]$Table, $Columns, $PrimaryKey, $ExpectedRows, $CatalogRows, [hashtable]$RedactedIds, [hashtable]$Spec)
    $colNames = @($Columns | ForEach-Object { $_.Name })
    $pkIndex = @($PrimaryKey | ForEach-Object { [array]::IndexOf($colNames, $_) })
    $expected = @{}
    foreach ($row in $ExpectedRows) {
        $tokens = foreach ($c in $Columns) {
            $v = $null
            if ($row.Contains($c.Name)) { $v = $row[$c.Name] }
            Get-ExpectedToken -Value $v -Column $c
        }
        $tokens = @($tokens)
        $key = ($pkIndex | ForEach-Object { $tokens[$_] }) -join '|'
        $redactId = $null
        if ($Spec -and $RedactedIds.ContainsKey($Table + ':' + [string]$row[$Spec.Id])) { $redactId = [string]$row[$Spec.Id] }
        $expected[$key] = [pscustomobject]@{ Tokens = $tokens; Redacted = $redactId }
    }
    $missing = 0; $extra = 0; $different = 0; $duplicate = 0
    $diffColumns = @{}; $nullMismatch = 0
    $badKeys = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($cells in $CatalogRows) {
        $cells = @($cells)
        if ($cells.Count -ne $colNames.Count) { $different++; continue }
        $key = ($pkIndex | ForEach-Object { $cells[$_] }) -join '|'
        if ($seen.ContainsKey($key)) { $duplicate++; continue }
        $seen[$key] = $true
        if (-not $expected.ContainsKey($key)) { $extra++; if ($badKeys.Count -lt 5) { $badKeys.Add('extra:' + (($pkIndex | ForEach-Object { Format-KeyToken $cells[$_] }) -join ',')) }; continue }
        $exp = $expected[$key]
        $rowBad = $false
        for ($i = 0; $i -lt $colNames.Count; $i++) {
            if ($exp.Redacted -and $colNames[$i] -eq $Spec.Template) {
                # A redacted template must be a reference token. Being equal to the source literal is a FAILURE here:
                # it would mean the secret travelled into the catalog.
                $text = ConvertFrom-TokenText $cells[$i]
                if ($null -ne $text -and [regex]::IsMatch($text, '^(?:.*=)?\{\{secret:RULE:' + [regex]::Escape($exp.Redacted) + '\}\}$')) { continue }
            }
            elseif ($cells[$i] -ceq $exp.Tokens[$i]) { continue }
            $rowBad = $true
            $diffColumns[$colNames[$i]] = 1 + [int]$diffColumns[$colNames[$i]]
            if (($cells[$i].StartsWith('null:')) -ne ($exp.Tokens[$i].StartsWith('null:'))) { $nullMismatch++ }
        }
        if ($rowBad) { $different++; if ($badKeys.Count -lt 5) { $badKeys.Add('different:' + (($pkIndex | ForEach-Object { Format-KeyToken $cells[$_] }) -join ',')) } }
    }
    foreach ($k in $expected.Keys) {
        if (-not $seen.ContainsKey($k)) {
            $missing++
            if ($badKeys.Count -lt 5) { $badKeys.Add('missing:' + (($k.Split('|') | ForEach-Object { Format-KeyToken $_ }) -join ',')) }
        }
    }
    return [pscustomobject]@{
        Expected = $expected.Count; Catalog = @($CatalogRows).Count; Missing = $missing; Extra = $extra; Different = $different
        Duplicate = $duplicate; DiffColumns = $diffColumns; NullMismatch = $nullMismatch; BadKeys = $badKeys.ToArray()
        Ok = ($missing -eq 0 -and $extra -eq 0 -and $different -eq 0 -and $duplicate -eq 0)
    }
}

function Get-SourceNeedles {
    # Literal secrets of the source that must not reach any catalog. Values are held in memory only.
    param($Source)
    $needles = [System.Collections.Generic.List[string]]::new()
    foreach ($table in $script:RedactionTables.Keys) {
        if (-not $script:CarriedTables.Contains($table)) { continue }
        $spec = $script:RedactionTables[$table]
        foreach ($row in $Source.Rows[$table]) {
            if (-not $row.Contains('IsSensitive') -or [int]$row['IsSensitive'] -ne 1) { continue }
            $template = [string]$row[$spec.Template]
            if ([string]::IsNullOrEmpty($template) -or [regex]::IsMatch($template, $script:PlaceholderPattern)) { continue }
            $m = [regex]::Match($template, '^(?i)([A-Za-z][A-Za-z0-9._-]*(?:password|secret|token|key)[A-Za-z0-9._-]*=)(\S+)$')
            if ($m.Success) { $needles.Add($m.Groups[2].Value) } else { $needles.Add($template) }
        }
    }
    foreach ($col in $script:ExcludedColumns['dbo.ManagedInstance']) {
        foreach ($row in $Source.Rows['dbo.ManagedInstance']) {
            if ($row.Contains($col) -and $row[$col] -is [string] -and $row[$col].Length -ge 6) { $needles.Add([string]$row[$col]) }
        }
    }
    return , $needles.ToArray()
}

function Get-StoredHashPairs {
    return @(
        @{ Table = 'cfg.LinksPageTemplate'; Hash = 'ContentSha256'; Content = @('ContentTemplate') },
        @{ Table = 'cfg.WebAccessTemplate'; Hash = 'ContentSha256'; Content = @('ContentTemplate') },
        @{ Table = 'cfg.LinksPagePresentationResource'; Hash = 'ContentSha256'; Content = @('ResourceText') },
        @{ Table = 'cfg.PulseResource'; Hash = 'ContentSha256'; Content = @('TextContent', 'BinaryContent') },
        @{ Table = 'cfg.LinksPageAsset'; Hash = 'ContentSha256'; Content = @('Content') },
        @{ Table = 'cfg.WebsiteBrandingAsset'; Hash = 'ContentSha256'; Content = @('BinaryContent') }
    )
}

function Get-TokenBytes {
    # Bytes of a text or blob token; $null for null and integer tokens.
    param([string]$Token)
    if ($Token.StartsWith('text:') -or $Token.StartsWith('blob:')) {
        $hex = $Token.Substring(5)
        if ($hex.Length -eq 0) { return [byte[]]::new(0) }
        return [Convert]::FromHexString($hex)
    }
    return $null
}

function Get-HashHexOfBytes {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash($Bytes)) } finally { $sha.Dispose() }
}

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

function New-TestResult {
    param([string]$Mode = '', [int]$Catalogs = 0)
    $failed = @($script:Checks | Where-Object { -not $_.ok }).Count
    return [pscustomobject]@{ Passed = ($script:Checks.Count - $failed); Failed = $failed; Mode = $Mode; Catalogs = $Catalogs; Checks = $script:Checks.ToArray() }
}

function Invoke-CatalogConversionTest {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string[]]$ExtraNeedles = @()
    )
    $script:Checks.Clear()
    if (-not (Test-Path -LiteralPath $Sqlite3 -PathType Leaf)) { throw ('sqlite3 was not found at: {0}' -f $Sqlite3) }
    $manifestPath = Join-Path $Folder 'conversion-manifest.json'

    # --- manifest --------------------------------------------------------------------
    $manifest = $null
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Add-Check 'manifest' 'conversion-manifest.json exists' $false; return (New-TestResult) }
    try { $manifest = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($manifestPath)) | ConvertFrom-Json } catch { Add-Check 'manifest' 'conversion-manifest.json is valid JSON' $false; return (New-TestResult) }
    Add-Check 'manifest' 'conversion-manifest.json is valid JSON, mode is cut or new-machine' ($manifest.contractVersion -eq '0.1-proposed' -and $manifest.mode -in @('cut', 'new-machine'))
    $mode = [string]$manifest.mode
    $entries = @($manifest.catalogs)
    $listed = @($entries | ForEach-Object { [string]$_.file })
    $onDisk = @(Get-ChildItem -LiteralPath $Folder -Filter 'catalog-*.db' -File | ForEach-Object { $_.Name })
    Add-Check 'manifest' 'the catalog files on disk are exactly the ones listed' ((@($onDisk | Where-Object { $listed -notcontains $_ }).Count -eq 0) -and (@($listed | Where-Object { $onDisk -notcontains $_ }).Count -eq 0)) ('listed {0}, on disk {1}' -f $listed.Count, $onDisk.Count)
    Add-Check 'manifest' 'no temporary build files are left in the folder' (@(Get-ChildItem -LiteralPath $Folder -File | Where-Object { $_.Name -like '*.tmp' -or $_.Name -like '*.build.sql' }).Count -eq 0)
    $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    Add-Check 'manifest' 'the manifest is ASCII with LF' (-not ($manifestBytes | Where-Object { $_ -gt 127 -or $_ -eq 13 }))
    foreach ($entry in $entries) {
        $path = Join-Path $Folder ([string]$entry.file)
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        $okHash = $exists -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq [string]$entry.sha256) -and ((Get-Item -LiteralPath $path).Length -eq [long]$entry.bytes)
        Add-Check 'manifest' ('{0}: SHA-256 and size equal the manifest' -f $entry.serverCode) $okHash
        if ($exists) {
            $meta = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $path, 'SELECT server_code || "|" || schema_version || "|" || cut_rule_version FROM catalog_meta;')).Trim()
            Add-Check 'manifest' ('{0}: catalog_meta agrees with the manifest' -f $entry.serverCode) ($meta -eq ('{0}|{1}|{2}' -f $entry.serverCode, $entry.schemaVersion, $entry.cutRuleVersion)) $meta
        }
    }

    # --- sqlite and exclusions ------------------------------------------------------------
    $expectedTables = @($script:CarriedTables.Keys | ForEach-Object { Get-SqliteTableName $_ }) + @('catalog_meta')
    $columnsByCatalog = @{}
    foreach ($entry in $entries) {
        $code = [string]$entry.serverCode
        $path = Join-Path $Folder ([string]$entry.file)
        $integrity = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $path, 'PRAGMA integrity_check;')).Trim()
        Add-Check 'sqlite' ('{0}: integrity_check' -f $code) ($integrity -eq 'ok')
        $fk = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $path, 'PRAGMA foreign_key_check;')).Trim()
        Add-Check 'sqlite' ('{0}: foreign_key_check is empty' -f $code) ($fk.Length -eq 0)
        $notStrict = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $path, "SELECT count(*) FROM pragma_table_list WHERE schema = 'main' AND strict = 0 AND name NOT LIKE 'sqlite_%';")).Trim()
        Add-Check 'sqlite' ('{0}: every table is STRICT' -f $code) ($notStrict -eq '0') ('tables that are not STRICT: ' + $notStrict)
        $uv = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $path, 'PRAGMA user_version;')).Trim()
        Add-Check 'sqlite' ('{0}: user_version equals the schema version' -f $code) ($uv -eq [string]$script:SchemaVersion) $uv
        Add-Check 'sqlite' ('{0}: a write is refused when opened read-only' -f $code) (Test-SqliteWriteRefused -Sqlite3 $Sqlite3 -Db $path)
        $cols = Get-CatalogColumns -Sqlite3 $Sqlite3 -Db $path
        $columnsByCatalog[$code] = $cols
        $tableNames = @($cols.Keys)
        $missingT = @($expectedTables | Where-Object { $tableNames -notcontains $_ })
        $extraT = @($tableNames | Where-Object { $expectedTables -notcontains $_ })
        Add-Check 'exclusions' ('{0}: the tables are exactly the 62 carried tables and catalog_meta' -f $code) ($missingT.Count -eq 0 -and $extraT.Count -eq 0) ('missing: {0}; unexpected: {1}' -f ($missingT -join ','), ($extraT -join ','))
        $retired = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $tableNames) {
            foreach ($c in $cols[$t]) {
                if ($c -match '^(ScriptText|ScriptSha256|RowVersion|ManagementDatabaseName|IisIdentityPassword|WebAccessPassword|MobileAppToken|SecretCipher)$') { $retired.Add($t + '.' + $c) }
            }
        }
        Add-Check 'exclusions' ('{0}: no secret, script, rowversion or retired column' -f $code) ($retired.Count -eq 0) ($retired -join ', ')
        Add-Check 'exclusions' ('{0}: no table of the secret schema (sec_ManagedCredential*)' -f $code) (@($tableNames | Where-Object { $_ -like 'sec_ManagedCredential*' }).Count -eq 0)
    }

    # --- values ------------------------------------------------------------------------------
    $owners = $null
    if ($mode -eq 'cut') { $owners = Get-ExpectedOwners -Source $Source }
    $redactedIds = @{}
    foreach ($entry in $entries) { foreach ($r in @($entry.redactedRules)) { $redactedIds[[string]$r] = $true } }
    $catalogData = @{}
    $globalDigests = @{}
    foreach ($entry in $entries) {
        $code = [string]$entry.serverCode
        $path = Join-Path $Folder ([string]$entry.file)
        $plan = [ordered]@{}
        foreach ($table in $script:CarriedTables.Keys) {
            $tn = Get-SqliteTableName $table
            $names = @($columnsByCatalog[$code][$tn])
            if ($names.Count -gt 0) { $plan[$tn] = $names }
        }
        $data = Read-CatalogRows -Sqlite3 $Sqlite3 -Db $path -Plan $plan
        $catalogData[$code] = $data
        $badTables = [System.Collections.Generic.List[string]]::new()
        $cellCount = 0; $rowCount = 0
        foreach ($table in $script:CarriedTables.Keys) {
            $tn = Get-SqliteTableName $table
            $class = $script:CarriedTables[$table]
            $cols = @(Get-CarriedColumns -Table $table -TableSchema $Source.Schema[$table])
            $catalogRows = @()
            if ($data.Contains($tn)) { $catalogRows = @($data[$tn]) }
            $actualNames = @($columnsByCatalog[$code][$tn])
            if (($actualNames -join ',') -ne (($cols | ForEach-Object { $_.Name }) -join ',')) { $badTables.Add($tn + ' (columns differ from the expected list)'); continue }
            $expectedRows = @()
            if ($class -eq 'G') { $expectedRows = @($Source.Rows[$table]) }
            elseif ($mode -eq 'cut') {
                if ($owners.Owned.ContainsKey($table) -and $owners.Owned[$table].ContainsKey($code)) { $expectedRows = @($owners.Owned[$table][$code]) }
            }
            if ($mode -eq 'new-machine' -and $table -eq 'dbo.ManagedServer') {
                $isOne = ($catalogRows.Count -eq 1)
                $codeOk = $false
                if ($isOne) { $idx = [array]::IndexOf(@($cols | ForEach-Object { $_.Name }), 'ServerCode'); $codeOk = ((ConvertFrom-TokenText $catalogRows[0][$idx]) -ceq $code) }
                if (-not ($isOne -and $codeOk)) { $badTables.Add($tn + ' (new machine: expected exactly its own server row)') }
                $rowCount += $catalogRows.Count
                continue
            }
            $spec = $null
            if ($script:RedactionTables.ContainsKey($table)) { $spec = $script:RedactionTables[$table] }
            $pk = Get-PrimaryKeyColumns -Schema $Source.Schema -Table $table -CarriedColumns $cols
            $cmp = Compare-TableRows -Table $table -Columns $cols -PrimaryKey $pk -ExpectedRows $expectedRows -CatalogRows $catalogRows -RedactedIds $redactedIds -Spec $spec
            $rowCount += $cmp.Catalog; $cellCount += $cmp.Catalog * $cols.Count
            if (-not $cmp.Ok) {
                $badTables.Add(('{0} (expected {1}, catalog {2}, missing {3}, extra {4}, different {5}, duplicate {6}; columns: {7}; first keys: {8})' -f $tn, $cmp.Expected, $cmp.Catalog, $cmp.Missing, $cmp.Extra, $cmp.Different, $cmp.Duplicate, (($cmp.DiffColumns.Keys | Sort-Object) -join ','), ($cmp.BadKeys -join ' ; ')))
            }
            if ($class -eq 'G') {
                $lines = @($catalogRows | ForEach-Object { $_ -join '|' } | Sort-Object)
                if (-not $globalDigests.ContainsKey($tn)) { $globalDigests[$tn] = @{} }
                $globalDigests[$tn][$code] = Get-HashHexOfBytes ([System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n")))
            }
        }
        Add-Check 'values' ('{0}: every carried table equals the source ({1} rows, {2} cells compared; counts, primary keys, nulls and values)' -f $code, $rowCount, $cellCount) ($badTables.Count -eq 0) ($badTables -join ' | ')
    }

    # --- cut completeness ----------------------------------------------------------------------
    if ($mode -eq 'cut') {
        $instCount = @($Source.Rows['dbo.ManagedInstance']).Count
        $seen = @{}; $dups = 0; $foreign = 0
        foreach ($entry in $entries) {
            $code = [string]$entry.serverCode
            $cols = @(Get-CarriedColumns -Table 'dbo.ManagedInstance' -TableSchema $Source.Schema['dbo.ManagedInstance'])
            $names = @($cols | ForEach-Object { $_.Name })
            $ic = [array]::IndexOf($names, 'InstanceCode'); $sc = [array]::IndexOf($names, 'ServerCode')
            foreach ($cells in @($catalogData[$code]['dbo_ManagedInstance'])) {
                $k = (ConvertFrom-TokenText $cells[$ic]).ToLowerInvariant()
                if ($seen.ContainsKey($k)) { $dups++ } else { $seen[$k] = $code }
                if (((ConvertFrom-TokenText $cells[$sc]).ToLowerInvariant()) -ne $code.ToLowerInvariant()) { $foreign++ }
            }
        }
        $allConverted = (@($entries).Count -eq @($Source.Rows['dbo.ManagedServer']).Count)
        if ($allConverted) { Add-Check 'cut' 'every instance of the source is in a catalog' ($seen.Count -eq $instCount) ('source {0}, placed {1}' -f $instCount, $seen.Count) }
        else { Add-Check 'cut' 'a subset of the machines was converted: the instances placed are all in the source' ($seen.Count -le $instCount) ('placed {0} of {1}' -f $seen.Count, $instCount) }
        Add-Check 'cut' 'no instance is in two catalogs' ($dups -eq 0) ('duplicates: ' + $dups)
        Add-Check 'cut' 'no instance row belongs to another machine' ($foreign -eq 0) ('foreign rows: ' + $foreign)
        $comp = $manifest.completeness
        $unplacedTotal = 0
        foreach ($t in $owners.Unplaced.Keys) { $unplacedTotal += $owners.Unplaced[$t] }
        $manifestUnplaced = 0
        foreach ($tbl in @($comp.tables)) { $manifestUnplaced += [int]$tbl.unplacedRows }
        Add-Check 'cut' 'rows that belong to no machine: the manifest reports as many as are recomputed here' ($manifestUnplaced -eq $unplacedTotal) ('recomputed {0}, manifest {1}' -f $unplacedTotal, $manifestUnplaced)
    }

    # --- global tables identical in every catalog ------------------------------------------------
    if (@($entries).Count -gt 1) {
        $differ = @($globalDigests.Keys | Where-Object { @($globalDigests[$_].Values | Select-Object -Unique).Count -gt 1 })
        Add-Check 'global' ('the {0} global tables have identical content in all {1} catalogs' -f $globalDigests.Count, @($entries).Count) ($differ.Count -eq 0) ($differ -join ', ')
    }

    # --- secrets ----------------------------------------------------------------------------------
    $needles = [System.Collections.Generic.List[string]]::new()
    foreach ($n in (Get-SourceNeedles -Source $Source)) { if ($n.Length -ge 6) { $needles.Add($n) } }
    foreach ($n in $ExtraNeedles) { if ($n.Length -ge 6) { $needles.Add($n) } }
    $latin1 = [System.Text.Encoding]::Latin1
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $entries) { $targets.Add(@{ Name = [string]$entry.file; Path = (Join-Path $Folder ([string]$entry.file)) }) }
    $targets.Add(@{ Name = 'conversion-manifest.json'; Path = $manifestPath })
    $leaks = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $targets) {
        $text = $latin1.GetString([System.IO.File]::ReadAllBytes($target.Path))
        $found = 0
        foreach ($n in $needles) {
            $needleText = $latin1.GetString([System.Text.UTF8Encoding]::new($false).GetBytes($n))
            if ($text.Contains($needleText, [System.StringComparison]::Ordinal)) { $found++ }
        }
        if ($found -gt 0) { $leaks.Add(('{0}: {1} secret value(s) found' -f $target.Name, $found)) }
    }
    Add-Check 'secrets' ('none of the {0} literal secrets of the source is in any catalog or in the manifest' -f $needles.Count) ($leaks.Count -eq 0) ($leaks -join '; ')
    $patterns = Get-SecretPatternTable
    foreach ($entry in $entries) {
        $code = [string]$entry.serverCode
        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($tn in $catalogData[$code].Keys) {
            foreach ($cells in $catalogData[$code][$tn]) {
                foreach ($cell in $cells) {
                    if (-not $cell.StartsWith('text:') -or $cell.Length -lt 21) { continue }
                    $s = ConvertFrom-TokenText $cell
                    if ($s.Length -lt 8) { continue }
                    $s = [regex]::Replace($s, '\{\{[^{}]*\}\}', '')
                    foreach ($p in $patterns.Keys) { if ([regex]::IsMatch($s, $patterns[$p])) { $hits.Add($tn + ':' + $p); break } }
                }
            }
        }
        $distinct = @($hits | Group-Object | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count })
        Add-Check 'secrets' ('{0}: no secret-like literal remains in any text cell' -f $code) ($hits.Count -eq 0) ($distinct -join '; ')
    }

    # --- stored hashes of the old system ------------------------------------------------------------
    foreach ($pair in (Get-StoredHashPairs)) {
        if (-not $script:CarriedTables.Contains($pair.Table)) { continue }
        $tn = Get-SqliteTableName $pair.Table
        $cols = @(Get-CarriedColumns -Table $pair.Table -TableSchema $Source.Schema[$pair.Table])
        $names = @($cols | ForEach-Object { $_.Name })
        $hi = [array]::IndexOf($names, $pair.Hash)
        if ($hi -lt 0) { continue }
        $matched = 0; $unmatched = 0; $broken = 0
        foreach ($entry in $entries) {
            $code = [string]$entry.serverCode
            foreach ($cells in @($catalogData[$code][$tn])) {
                $stored = (ConvertFrom-TokenText $cells[$hi])
                if ([string]::IsNullOrEmpty($stored)) { continue }
                foreach ($cn in $pair.Content) {
                    $ci = [array]::IndexOf($names, $cn)
                    if ($ci -lt 0) { continue }
                    $bytes = Get-TokenBytes $cells[$ci]
                    if ($null -eq $bytes) { continue }
                    $isText = $cells[$ci].StartsWith('text:')
                    $candidates = @((Get-HashHexOfBytes $bytes))
                    if ($isText) { $candidates += (Get-HashHexOfBytes ([System.Text.Encoding]::Unicode.GetBytes((ConvertFrom-TokenText $cells[$ci])))) }
                    if ($candidates -contains $stored.ToUpperInvariant()) { $matched++ } else { $unmatched++ }
                }
            }
        }
        # A row that never matched its stored hash in the source cannot be told apart here; the "values" group
        # already proved equality with the source, so a non-match is reported for information only when the
        # source itself matched. We recompute the source side to decide.
        $srcMatched = 0
        foreach ($row in $Source.Rows[$pair.Table]) {
            if ($null -eq $row[$pair.Hash]) { continue }
            foreach ($cn in $pair.Content) {
                $v = $null; if ($row.Contains($cn)) { $v = $row[$cn] }
                if ($null -eq $v) { continue }
                $b = if ($v -is [byte[]]) { $v } else { [System.Text.Encoding]::Unicode.GetBytes([string]$v) }
                $h = ([string]$row[$pair.Hash]).Trim().ToUpperInvariant()
                $h1 = Get-HashHexOfBytes $b
                $h2 = if ($v -is [string]) { Get-HashHexOfBytes ([System.Text.Encoding]::Unicode.GetBytes($v)) } else { '' }
                if ($h -eq $h1 -or $h -eq $h2) { $srcMatched++ }
            }
        }
        $expectedMatches = $srcMatched * @($entries).Count
        Add-Check 'stored-hash' ('{0}: the stored {1} matches the catalog content as often as it matches the source' -f $tn, $pair.Hash) ($matched -ge $expectedMatches) ('matching cells {0}, expected at least {1}; non-matching {2}' -f $matched, $expectedMatches, $unmatched)
    }

    return (New-TestResult -Mode $mode -Catalogs @($entries).Count)
}

function Write-TestReport {
    param($Result, [string]$Path)
    $report = [ordered]@{
        contractVersion = '0.1-proposed'
        tool            = 'Test-CatalogConversion'
        toolVersion     = $script:TestToolVersion
        mode            = $Result.Mode
        catalogs        = $Result.Catalogs
        passed          = $Result.Passed
        failed          = $Result.Failed
        checks          = $Result.Checks
    }
    $json = ($report | ConvertTo-Json -Depth 6 -EscapeHandling EscapeNonAscii)
    $json = ($json -replace "`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllBytes($Path, [System.Text.UTF8Encoding]::new($false).GetBytes($json))
}

if ($MyInvocation.InvocationName -ne '.') {
    $tables = @($script:CarriedTables.Keys)
    if ($script:Cli.ParameterSet -eq 'Sync') {
        $resolved = (Resolve-Path -LiteralPath $script:Cli.SyncFile).Path
        Write-Host ('Reading {0}...' -f (Split-Path -Leaf $resolved))
        $text = [System.IO.File]::ReadAllText($resolved, [System.Text.UTF8Encoding]::new($false))
        $schema = Read-SyncSchema -Text $text -Tables $tables
        $source = [pscustomobject]@{ Schema = $schema; Rows = (Read-SyncRows -Text $text -Schema $schema) }
    }
    else {
        $source = Read-SqlServerSource -Instance $script:Cli.SqlInstance -DatabaseName $script:Cli.Database -ClientPath $script:Cli.SqlClientPath -Tables $tables -TrustCertificate:$script:Cli.Trust
    }
    $result = Invoke-CatalogConversionTest -Source $source -Folder $script:Cli.CatalogFolder -Sqlite3 $script:Cli.Sqlite3Path -ExtraNeedles $script:Cli.ExtraNeedle
    Write-Host ('{0} passed, {1} failed ({2} mode, {3} catalog(s))' -f $result.Passed, $result.Failed, $result.Mode, $result.Catalogs)
    if ($script:Cli.ReportPath) { Write-TestReport -Result $result -Path $script:Cli.ReportPath }
    if ($result.Failed -gt 0) { exit 1 }
}
