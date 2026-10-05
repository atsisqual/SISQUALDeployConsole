#requires -Version 7.0
<#
.SYNOPSIS
    Seals a portable package folder: validates the catalog, recomputes the SHA-256 of every file,
    writes the package manifest and has it signed by the credential tool.

.DESCRIPTION
    Step B5 of docs/migration/catalog-conversion-plan.md (section 5.3, ADR-0007 item 7).
    Used (a) once after the conversion, to produce the first manifest, and (b) every time the owner
    edits the catalog by hand, or any other file of the package changes, to produce a new one.
    Without a valid manifest the application refuses to start.

    What it does, in this order, and writes nothing until the very end:
      1. lists the files of the package folder (refuses forbidden files, unsafe names, case
         duplicates and links) and hashes them;
      2. validates the catalog: SQLite file, integrity_check, foreign_key_check, user_version,
         one catalog_meta row that agrees with the manifest, no secret table or column, and a scan of
         every text cell for secret-like literals (the same patterns as Convert-ManagementDb.ps1);
      3. when the catalog was edited, records that in catalog_meta (source_kind manual-edit-sealed)
         on a temporary copy;
      4. builds the manifest (contracts/package-manifest.schema.json), shows a summary of what
         changed (file names and table names, never values) and asks the owner to confirm;
      5. gets a signature from the signer, then replaces the catalog, writes the manifest and appends
         a line to the seal log. If anything fails the original catalog is restored.

    SIGNING. This tool contains NO signature algorithm and never sees a private key. The algorithm
    and the key belong to the credential tool, and the credential contract leaves them [PENDING]
    owner approval. The tool passes the canonical bytes of the manifest to a signer script and
    stores what it returns:
        pwsh -NoProfile -File <Signer> -InputFile <canonical bytes> -OutputFile <result.json>
    result.json: { "issuerKeyId": "<64 lowercase hex>", "algorithm": "<id>", "value": "<base64>" }.
    A verifier script (-Verifier, same shape: -InputFile -SignatureFile, exit 0 when valid) is used
    by -VerifyOnly. -Unsigned writes a manifest WITHOUT a signature, for development only: the
    application refuses it unless started with its logged development flag.

    CANONICAL FORM [PROPOSED]. The signed bytes are the manifest without its "signature" member as
    compact JSON: object keys in ordinal order, arrays in their stored order (files sorted by path),
    no insignificant whitespace, strings escaped as in RFC 8785 with every non-ASCII character as
    \uXXXX (the schema allows only ASCII), integers as plain digits. For this manifest this is the
    JSON Canonicalization Scheme (RFC 8785). Needs owner approval with the credential contract (Q2).

    No file of the package is read for its content except the catalog (to validate it) and hashing.
    No secret value is printed or logged: reports carry counts, file names and table names only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageFolder,
    [Parameter(Mandatory)][string]$Sqlite3Path,

    [string]$SignerScript,
    [string]$VerifierScript,
    [switch]$Unsigned,
    [switch]$VerifyOnly,

    # First seal only (when there is no package-manifest.json yet)
    [string]$ProductVersion,
    [string]$CatalogRelativePath,
    [string]$ConversionManifest,

    [ValidateSet('conversion-tool', 'manual-edit-sealed', 'build')]
    [string]$Origin,
    [string]$Baseline,
    [string]$Note = '',
    [string]$SealLog,
    [switch]$Yes,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolVersion = '0.1.0'
$script:ManifestName = 'package-manifest.json'
$script:ContractVersion = '0.1-proposed'
$script:SupportedSchemaVersions = @(1)
$script:RelativePathPattern = '^(?!/)(?![A-Za-z]:)(?!.*(^|/)\.{1,2}(/|$))(?!.*//)[A-Za-z0-9._ \-/]+$'

# Files that must never be listed in a package (credentials and logs live outside it).
$script:ForbiddenPatterns = @('credentials*.db', 'credentials*.pkg', '*.vault', '*.pfx', '*.pem', '*.key', '*.snk', '*.log', '*.bak', '*.tmp', '*.build.sql')
# Retired or secret columns and tables (plan section 3).
$script:ForbiddenColumns = @('IisIdentityPassword', 'WebAccessPassword', 'MobileAppToken', 'ScriptText', 'ScriptSha256', 'RowVersion', 'ManagementDatabaseName', 'SecretCipher')
$script:ForbiddenTablePatterns = @('sec_ManagedCredential*')

# ---------------------------------------------------------------------------
# Canonical form
# ---------------------------------------------------------------------------

function ConvertTo-CanonicalString {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            8 { [void]$sb.Append('\b') }
            9 { [void]$sb.Append('\t') }
            10 { [void]$sb.Append('\n') }
            12 { [void]$sb.Append('\f') }
            13 { [void]$sb.Append('\r') }
            default {
                if ($code -lt 32 -or $code -gt 126) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-CanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-CanonicalString $Value) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return ([long]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        [string[]]$keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        $parts = foreach ($k in $keys) { (ConvertTo-CanonicalString $k) + ':' + (ConvertTo-CanonicalJson $Value[$k]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $table = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $table[$p.Name] = $p.Value }
        return (ConvertTo-CanonicalJson $table)
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = foreach ($item in $Value) { ConvertTo-CanonicalJson $item }
        return '[' + (@($items) -join ',') + ']'
    }
    throw ('Value of type {0} cannot be written in canonical form.' -f $Value.GetType().FullName)
}

function Get-CanonicalManifestBytes {
    # The manifest without its signature member.
    param($Manifest)
    $copy = [ordered]@{}
    if ($Manifest -is [System.Collections.IDictionary]) { foreach ($k in $Manifest.Keys) { $copy[[string]$k] = $Manifest[$k] } }
    else { foreach ($p in $Manifest.PSObject.Properties) { $copy[$p.Name] = $p.Value } }
    [void]$copy.Remove('signature')
    return [System.Text.Encoding]::ASCII.GetBytes((ConvertTo-CanonicalJson $copy))
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

function Get-Sha256Hex {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-FileSha256Hex {
    param([string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($stream)) -replace '-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Get-PackageFiles {
    # Every file of the folder except the manifest at the root. Returns problems instead of throwing,
    # so that all of them are reported together.
    param([string]$Folder)
    $root = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $files = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($root)
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($dir)) {
            $info = [System.IO.FileInfo]::new($entry)
            $rel = [System.IO.Path]::GetRelativePath($root, $entry).Replace('\', '/')
            if (($info.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $problems.Add(('{0}: a link is not allowed in a package.' -f $rel)); continue }
            if (($info.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) { $stack.Push($entry); continue }
            if ($rel -ceq $script:ManifestName) { continue }
            if ($rel.Length -gt 240 -or $rel -notmatch $script:RelativePathPattern) { $problems.Add(('{0}: the path is not allowed in a manifest (ASCII letters, digits, space, . _ - and / only, at most 240 characters).' -f $rel)); continue }
            $leaf = [System.IO.Path]::GetFileName($entry)
            $blocked = @($script:ForbiddenPatterns | Where-Object { $leaf -like $_ })
            if ($blocked.Count -gt 0) { $problems.Add(('{0}: files of this kind must never be inside a package (matches {1}).' -f $rel, $blocked[0])); continue }
            $key = $rel.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { $problems.Add(('{0}: differs from {1} only by case.' -f $rel, $seen[$key])); continue }
            $seen[$key] = $rel
            $files.Add([pscustomobject]@{ Path = $rel; FullName = $entry; Bytes = $info.Length })
        }
    }
    foreach ($f in $files) { $f | Add-Member -NotePropertyName Sha256 -NotePropertyValue (Get-FileSha256Hex -Path $f.FullName) }
    [string[]]$order = @($files | ForEach-Object { $_.Path })
    [Array]::Sort($order, [System.StringComparer]::Ordinal)
    $byPath = @{}
    foreach ($f in $files) { $byPath[$f.Path] = $f }
    $ordered = @($order | ForEach-Object { $byPath[$_] })
    return [pscustomobject]@{ Files = $ordered; Problems = $problems.ToArray() }
}

# ---------------------------------------------------------------------------
# SQLite
# ---------------------------------------------------------------------------

function Invoke-Sqlite3 {
    param([string]$Exe, [string[]]$Arguments)
    $psi = [System.Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($a in $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()
    $proc.StandardInput.Close()
    $proc.WaitForExit()
    $out = $outTask.GetAwaiter().GetResult()
    $err = $errTask.GetAwaiter().GetResult()
    if ($proc.ExitCode -ne 0 -or $err.Trim().Length -gt 0) {
        $text = $err.Trim()
        if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + ' ...' }
        throw ('sqlite3 failed (exit {0}): {1}' -f $proc.ExitCode, $text)
    }
    return $out
}

function Get-SecretPatternTable {
    # Same patterns as Convert-ManagementDb.ps1 (a unit test compares them).
    $literal = '[^\s''",;\\{$%<)\[][^\s''",;\\{$%<)]{5,}'
    return [ordered]@{
        passwordLiteral         = '(?i)\b(password|pwd|passwd)\s*[=:]\s*' + $literal
        secretLiteral           = '(?i)\b(secret|apikey|api_key|token)\s*[=:]\s*' + $literal
        connectionUserAndSecret = '(?i)User ID\s*=\s*[^;]+;\s*Password\s*='
        privateKeyBlock         = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    }
}

function Get-CatalogTextCells {
    # Yields [table, column, text] for every TEXT cell of 8 or more characters, read through hex() so that
    # line breaks inside a value cannot confuse the reader.
    param([string]$Sqlite3, [string]$Db, [string[]]$Tables)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($t in $Tables) {
        $cols = @((Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, ("SELECT name FROM pragma_table_info('{0}') WHERE lower(type) = 'text' ORDER BY cid;" -f $t.Replace("'", "''")))) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
        if ($cols.Count -eq 0) { continue }
        $expr = ($cols | ForEach-Object { "CASE WHEN typeof(`"$_`") = 'text' AND length(`"$_`") >= 8 THEN hex(`"$_`") ELSE '' END" }) -join " || ',' || "
        $out = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, ("SELECT {0} FROM `"{1}`";" -f $expr, $t.Replace('"', '""')))
        foreach ($line in ($out -split "`n")) {
            $line = $line.TrimEnd("`r")
            if ($line.Length -eq 0) { continue }
            $parts = $line.Split(',')
            for ($i = 0; $i -lt $parts.Count -and $i -lt $cols.Count; $i++) {
                if ($parts[$i].Length -eq 0) { continue }
                $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromHexString($parts[$i]))
                $result.Add([pscustomobject]@{ Table = $t; Column = $cols[$i]; Text = $text })
            }
        }
    }
    return , $result.ToArray()
}

function Test-CatalogFile {
    # Returns [pscustomobject]@{ Problems = string[]; Meta = object }. Problems never contain cell values.
    param([string]$Sqlite3, [string]$Db, [string]$ExpectedServerCode = '')
    $problems = [System.Collections.Generic.List[string]]::new()
    $meta = $null
    $header = [byte[]]::new(16)
    $stream = [System.IO.File]::OpenRead($Db)
    try { [void]$stream.Read($header, 0, 16) } finally { $stream.Dispose() }
    if ([System.Text.Encoding]::ASCII.GetString($header) -ne ("SQLite format 3" + [char]0)) {
        $problems.Add('The catalog is not a SQLite database file.')
        return [pscustomobject]@{ Problems = $problems.ToArray(); Meta = $null }
    }
    try {
        $integrity = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, 'PRAGMA integrity_check;')).Trim()
        if ($integrity -ne 'ok') { $problems.Add('integrity_check did not answer ok.') }
        $fk = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, 'PRAGMA foreign_key_check;')).Trim()
        if ($fk.Length -gt 0) { $problems.Add('foreign_key_check reported violations.') }
        $uv = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, 'PRAGMA user_version;')).Trim()
        if ($script:SupportedSchemaVersions -notcontains [int]$uv) { $problems.Add(('user_version {0} is not a supported schema version.' -f $uv)) }

        $tables = @((Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
        foreach ($t in $tables) {
            foreach ($pattern in $script:ForbiddenTablePatterns) { if ($t -like $pattern) { $problems.Add(('Table {0} must not be in a catalog (secrets).' -f $t)) } }
        }
        $colRows = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, "SELECT m.name || '.' || p.name FROM sqlite_master m, pragma_table_info(m.name) p WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%';")) -split "`n"
        foreach ($c in $colRows) {
            $c = $c.Trim()
            if ($c.Length -eq 0) { continue }
            $colName = $c.Substring($c.IndexOf('.') + 1)
            if ($script:ForbiddenColumns -contains $colName) { $problems.Add(('Column {0} must not be in a catalog.' -f $c)) }
        }

        if ($tables -notcontains 'catalog_meta') { $problems.Add('The catalog has no catalog_meta table.') }
        else {
            $count = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, 'SELECT count(*) FROM catalog_meta;')).Trim()
            if ($count -ne '1') { $problems.Add(('catalog_meta must hold exactly one row (found {0}).' -f $count)) }
            else {
                $row = (Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, "SELECT schema_version || '|' || server_code || '|' || source_kind || '|' || built_at_utc || '|' || cut_rule_version FROM catalog_meta;")).Trim().Split('|')
                if ($row.Count -ne 5) { $problems.Add('catalog_meta has an unexpected shape.') }
                else {
                    $meta = [pscustomobject]@{ SchemaVersion = [int]$row[0]; ServerCode = $row[1]; SourceKind = $row[2]; BuiltAtUtc = $row[3]; CutRuleVersion = [int]$row[4] }
                    if ($meta.SchemaVersion -ne [int]$uv) { $problems.Add('catalog_meta.schema_version differs from user_version.') }
                    if ($row[1] -notmatch '^[A-Za-z0-9_-]{1,60}$') { $problems.Add('catalog_meta.server_code is not a valid ServerCode.') }
                    if ($ExpectedServerCode.Length -gt 0 -and $row[1] -cne $ExpectedServerCode) { $problems.Add('catalog_meta.server_code differs from the server code recorded in the manifest.') }
                    if (@('conversion-tool', 'manual-edit-sealed', 'build') -notcontains $row[2]) { $problems.Add('catalog_meta.source_kind is not a known kind.') }
                }
            }
        }

        $patterns = Get-SecretPatternTable
        $hits = @{}
        foreach ($cell in (Get-CatalogTextCells -Sqlite3 $Sqlite3 -Db $Db -Tables ($tables | Where-Object { $_ -ne 'catalog_meta' }))) {
            $text = [regex]::Replace($cell.Text, '\{\{[^{}]*\}\}', '')
            foreach ($p in $patterns.Keys) {
                $n = [regex]::Matches($text, $patterns[$p]).Count
                if ($n -gt 0) { $k = '{0}.{1} ({2})' -f $cell.Table, $cell.Column, $p; $hits[$k] = [int]$hits[$k] + $n }
            }
        }
        foreach ($k in ($hits.Keys | Sort-Object)) { $problems.Add(('Secret-like literal in {0}: {1} cell(s).' -f $k, $hits[$k])) }
    }
    catch { $problems.Add(('The catalog could not be read: {0}' -f $_.Exception.Message)) }
    return [pscustomobject]@{ Problems = $problems.ToArray(); Meta = $meta }
}

function Get-TableDigests {
    # Per table: SHA-256 over the sorted rows, each cell as typeof:hex, and the row count. Used for the change summary.
    param([string]$Sqlite3, [string]$Db)
    $result = [ordered]@{}
    $tables = @((Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    foreach ($t in $tables) {
        $cols = @((Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, ("SELECT name FROM pragma_table_info('{0}') ORDER BY cid;" -f $t.Replace("'", "''")))) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
        $expr = ($cols | ForEach-Object { "typeof(`"$_`") || ':' || hex(`"$_`")" }) -join " || '|' || "
        $out = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $Db, ("SELECT {0} AS r FROM `"{1}`" ORDER BY r;" -f $expr, $t.Replace('"', '""')))
        $lines = @($out -split "`n" | Where-Object { $_.Trim().Length -gt 0 })
        $result[$t] = [pscustomobject]@{ Rows = $lines.Count; Digest = (Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($out))) }
    }
    return $result
}

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

function Test-ManifestStructure {
    # Mirrors contracts/package-manifest.schema.json (required members, patterns, types). Returns problems.
    param($Manifest)
    $problems = [System.Collections.Generic.List[string]]::new()
    $has = { param($o, $n) $null -ne $o -and $null -ne $o.PSObject.Properties[$n] }
    foreach ($n in @('contractVersion', 'packageId', 'productVersion', 'builtAt', 'catalog', 'files')) {
        if (-not (& $has $Manifest $n)) { $problems.Add(('The manifest has no "{0}".' -f $n)) }
    }
    if ($problems.Count -gt 0) { return $problems.ToArray() }
    if ($Manifest.contractVersion -cne $script:ContractVersion) { $problems.Add('contractVersion is not the supported one.') }
    if ($Manifest.packageId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { $problems.Add('packageId is not a lower-case UUID.') }
    if ($Manifest.productVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { $problems.Add('productVersion is not a semantic version.') }
    if ($Manifest.builtAt -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { $problems.Add('builtAt is not a UTC time.') }
    $cat = $Manifest.catalog
    foreach ($n in @('serverCode', 'file', 'schemaVersion', 'origin')) { if (-not (& $has $cat $n)) { $problems.Add(('catalog has no "{0}".' -f $n)) } }
    if ($problems.Count -gt 0) { return $problems.ToArray() }
    if ($cat.serverCode -notmatch '^[A-Za-z0-9_-]{1,60}$') { $problems.Add('catalog.serverCode is not valid.') }
    if ([string]$cat.file -notmatch $script:RelativePathPattern) { $problems.Add('catalog.file is not a valid relative path.') }
    if ($cat.schemaVersion -isnot [int] -and $cat.schemaVersion -isnot [long]) { $problems.Add('catalog.schemaVersion is not an integer.') }
    elseif ($cat.schemaVersion -lt 1) { $problems.Add('catalog.schemaVersion must be 1 or more.') }
    if (@('conversion-tool', 'manual-edit-sealed', 'build') -notcontains $cat.origin) { $problems.Add('catalog.origin is not a known origin.') }
    if ((& $has $cat 'originReference') -and ([string]$cat.originReference -notmatch '^[\x20-\x7E]{0,200}$')) { $problems.Add('catalog.originReference is not printable ASCII of at most 200 characters.') }
    $listed = @($Manifest.files)
    if ($listed.Count -lt 1) { $problems.Add('files is empty.') }
    $names = @{}
    foreach ($f in $listed) {
        foreach ($n in @('path', 'sha256', 'size')) { if (-not (& $has $f $n)) { $problems.Add(('A file entry has no "{0}".' -f $n)) } }
        if ($null -eq $f.PSObject.Properties['path'] -or $null -eq $f.PSObject.Properties['sha256'] -or $null -eq $f.PSObject.Properties['size']) { continue }
        if ([string]$f.path -notmatch $script:RelativePathPattern) { $problems.Add(('{0}: not a valid relative path.' -f $f.path)) }
        if ([string]$f.sha256 -notmatch '^[0-9a-f]{64}$') { $problems.Add(('{0}: sha256 is not 64 lower-case hex.' -f $f.path)) }
        if ($f.size -isnot [int] -and $f.size -isnot [long]) { $problems.Add(('{0}: size is not an integer.' -f $f.path)) }
        $k = ([string]$f.path).ToLowerInvariant()
        if ($names.ContainsKey($k)) { $problems.Add(('{0}: listed twice (ignoring case).' -f $f.path)) }
        $names[$k] = $true
    }
    if (@($listed | Where-Object { $_.path -ceq $cat.file }).Count -ne 1) { $problems.Add('catalog.file must be listed exactly once in files.') }
    if (-not (& $has $Manifest 'signature') -or $null -eq $Manifest.signature) { $problems.Add('The manifest has no "signature".') }
    else {
        $sig = $Manifest.signature
        foreach ($n in @('issuerKeyId', 'algorithm', 'value')) { if (-not (& $has $sig $n)) { $problems.Add(('signature has no "{0}".' -f $n)) } }
        if ((& $has $sig 'issuerKeyId') -and [string]$sig.issuerKeyId -notmatch '^[0-9a-f]{64}$') { $problems.Add('signature.issuerKeyId is not 64 lower-case hex.') }
        if ((& $has $sig 'algorithm') -and [string]$sig.algorithm -notmatch '^[A-Za-z0-9._+-]{3,40}$') { $problems.Add('signature.algorithm is not a valid identifier.') }
        if ((& $has $sig 'value') -and ([string]$sig.value -notmatch '^[A-Za-z0-9+/]+={0,2}$' -or ([string]$sig.value).Length -lt 16 -or ([string]$sig.value).Length -gt 2048)) { $problems.Add('signature.value is not base64 of 16 to 2048 characters.') }
    }
    return $problems.ToArray()
}

function Read-ManifestFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if (@($bytes | Where-Object { $_ -gt 127 -or $_ -eq 13 }).Count -gt 0) { throw 'The manifest is not ASCII with LF.' }
    return ([System.Text.Encoding]::ASCII.GetString($bytes) | ConvertFrom-Json -DateKind String)
}

function Write-ManifestFile {
    param([string]$Path, $Manifest)
    $json = ($Manifest | ConvertTo-Json -Depth 8 -EscapeHandling EscapeNonAscii)
    $json = ($json -replace "`r`n", "`n") + "`n"
    $temp = $Path + '.tmp'
    [System.IO.File]::WriteAllBytes($temp, [System.Text.Encoding]::ASCII.GetBytes($json))
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

# ---------------------------------------------------------------------------
# Signer / verifier (external, supplied by the credential tool)
# ---------------------------------------------------------------------------

function Invoke-Signer {
    param([string]$Script, [byte[]]$Bytes)
    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw ('The signer script was not found: {0}' -f $Script) }
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('seal-sign-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $inFile = Join-Path $dir 'canonical.bin'
        $outFile = Join-Path $dir 'signature.json'
        [System.IO.File]::WriteAllBytes($inFile, $Bytes)
        $pwsh = (Get-Process -Id $PID).Path
        $log = & $pwsh -NoProfile -File $Script -InputFile $inFile -OutputFile $outFile 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw ('The signer failed (exit {0}).' -f $LASTEXITCODE) }
        if (-not (Test-Path -LiteralPath $outFile)) { throw 'The signer wrote no result.' }
        $res = [System.IO.File]::ReadAllText($outFile) | ConvertFrom-Json -DateKind String
        $sig = [ordered]@{ issuerKeyId = [string]$res.issuerKeyId; algorithm = [string]$res.algorithm; value = [string]$res.value }
        $probe = [pscustomobject]@{ signature = [pscustomobject]$sig }
        # The function returns the array wrapped (comma operator), so assign it without @().
        $bad = Test-SignatureShape $probe.signature
        if ($bad.Count -gt 0) { throw ('The signer returned an invalid signature: {0}' -f ($bad -join ' ')) }
        return $sig
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

function Test-SignatureShape {
    param($Sig)
    $p = [System.Collections.Generic.List[string]]::new()
    if ([string]$Sig.issuerKeyId -notmatch '^[0-9a-f]{64}$') { $p.Add('issuerKeyId is not 64 lower-case hex.') }
    if ([string]$Sig.algorithm -notmatch '^[A-Za-z0-9._+-]{3,40}$') { $p.Add('algorithm is not a valid identifier.') }
    if ([string]$Sig.value -notmatch '^[A-Za-z0-9+/]+={0,2}$' -or ([string]$Sig.value).Length -lt 16 -or ([string]$Sig.value).Length -gt 2048) { $p.Add('value is not base64 of 16 to 2048 characters.') }
    return , $p.ToArray()
}

function Invoke-Verifier {
    param([string]$Script, [byte[]]$Bytes, $Sig)
    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) { throw ('The verifier script was not found: {0}' -f $Script) }
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ('seal-verify-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $inFile = Join-Path $dir 'canonical.bin'
        $sigFile = Join-Path $dir 'signature.json'
        [System.IO.File]::WriteAllBytes($inFile, $Bytes)
        [System.IO.File]::WriteAllText($sigFile, ($Sig | ConvertTo-Json -Compress))
        $pwsh = (Get-Process -Id $PID).Path
        $null = & $pwsh -NoProfile -File $Script -InputFile $inFile -SignatureFile $sigFile 2>&1 | Out-String
        return ($LASTEXITCODE -eq 0)
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
# Verify
# ---------------------------------------------------------------------------

function Invoke-PackageVerification {
    param([string]$Folder, [string]$Sqlite3, [string]$Verifier)
    $problems = [System.Collections.Generic.List[string]]::new()
    $manifestPath = Join-Path $Folder $script:ManifestName
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return [pscustomobject]@{ Ok = $false; Problems = @('There is no package-manifest.json.'); Signature = 'none' } }
    $manifest = $null
    try { $manifest = Read-ManifestFile -Path $manifestPath } catch { return [pscustomobject]@{ Ok = $false; Problems = @(('The manifest cannot be read: {0}' -f $_.Exception.Message)); Signature = 'none' } }
    foreach ($p in (Test-ManifestStructure -Manifest $manifest)) { $problems.Add($p) }
    if (@($problems | Where-Object { $_ -notlike 'The manifest has no "signature"*' }).Count -gt 0) { return [pscustomobject]@{ Ok = $false; Problems = $problems.ToArray(); Signature = 'none' } }

    $scan = Get-PackageFiles -Folder $Folder
    foreach ($p in $scan.Problems) { $problems.Add($p) }
    $onDisk = @{}
    foreach ($f in $scan.Files) { $onDisk[$f.Path] = $f }
    $listed = @{}
    foreach ($e in @($manifest.files)) {
        $listed[[string]$e.path] = $true
        if (-not $onDisk.ContainsKey([string]$e.path)) { $problems.Add(('{0}: listed but missing.' -f $e.path)); continue }
        $f = $onDisk[[string]$e.path]
        if ([long]$e.size -ne [long]$f.Bytes) { $problems.Add(('{0}: size differs from the manifest.' -f $e.path)) }
        if ([string]$e.sha256 -cne $f.Sha256) { $problems.Add(('{0}: SHA-256 differs from the manifest.' -f $e.path)) }
    }
    foreach ($path in $onDisk.Keys) { if (-not $listed.ContainsKey($path)) { $problems.Add(('{0}: in the folder but not in the manifest.' -f $path)) } }

    $catalogPath = Join-Path $Folder ([string]$manifest.catalog.file)
    if (Test-Path -LiteralPath $catalogPath -PathType Leaf) {
        $check = Test-CatalogFile -Sqlite3 $Sqlite3 -Db $catalogPath -ExpectedServerCode ([string]$manifest.catalog.serverCode)
        foreach ($p in $check.Problems) { $problems.Add(('catalog: {0}' -f $p)) }
        if ($null -ne $check.Meta) {
            if ($check.Meta.SchemaVersion -ne [int]$manifest.catalog.schemaVersion) { $problems.Add('catalog: catalog_meta.schema_version differs from the manifest.') }
            if ($check.Meta.SourceKind -cne [string]$manifest.catalog.origin) { $problems.Add('catalog: catalog_meta.source_kind differs from the manifest origin.') }
        }
    }
    $sigState = 'unsigned'
    if ($null -ne $manifest.PSObject.Properties['signature'] -and $null -ne $manifest.signature) {
        $sigState = 'present, not verified (no -VerifierScript)'
        if ($Verifier) {
            $ok = Invoke-Verifier -Script $Verifier -Bytes (Get-CanonicalManifestBytes -Manifest $manifest) -Sig $manifest.signature
            if ($ok) { $sigState = 'valid' } else { $sigState = 'INVALID'; $problems.Add('The signature does not verify against the manifest.') }
        }
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = $problems.ToArray(); Signature = $sigState }
}

# ---------------------------------------------------------------------------
# Seal
# ---------------------------------------------------------------------------

function Invoke-Seal {
    param(
        [string]$Folder, [string]$Sqlite3, [string]$Signer, [bool]$AllowUnsigned,
        [string]$Version, [string]$CatalogRel, [string]$ConversionManifestPath, [string]$ForcedOrigin,
        [string]$BaselineDb, [string]$NoteText, [string]$LogPath, [bool]$Confirmed, [bool]$Preview
    )
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw ('The package folder was not found: {0}' -f $Folder) }
    if (-not (Test-Path -LiteralPath $Sqlite3 -PathType Leaf)) { throw ('sqlite3 was not found at: {0}' -f $Sqlite3) }
    if ($NoteText -notmatch '^[\x20-\x7E]{0,120}$') { throw 'The note must be printable ASCII of at most 120 characters.' }
    if (-not $Signer -and -not $AllowUnsigned) { throw 'No signer was given. Pass -SignerScript (provided by the credential tool) or, for development only, -Unsigned.' }
    $root = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $manifestPath = Join-Path $root $script:ManifestName

    $previous = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $previous = Read-ManifestFile -Path $manifestPath
        $structure = @(Test-ManifestStructure -Manifest $previous | Where-Object { $_ -notlike 'The manifest has no "signature"*' })
        if ($structure.Count -gt 0) { throw ('The existing manifest is not valid: {0}' -f ($structure -join ' ')) }
    }

    # 1. Files
    $scan = Get-PackageFiles -Folder $root
    if ($scan.Problems.Count -gt 0) { throw ("The package folder has problems:`n  " + ($scan.Problems -join "`n  ")) }
    if ($scan.Files.Count -eq 0) { throw 'The package folder has no files.' }

    # Which file is the catalog
    $catalogRelPath = $CatalogRel
    if ($null -ne $previous) { $catalogRelPath = [string]$previous.catalog.file }
    elseif (-not $catalogRelPath) {
        $found = @($scan.Files | Where-Object { $_.Path -like 'catalog/catalog-*.db' })
        if ($found.Count -ne 1) { throw 'Exactly one catalog/catalog-<ServerCode>.db was expected; pass -CatalogRelativePath.' }
        $catalogRelPath = $found[0].Path
    }
    $catalogEntry = @($scan.Files | Where-Object { $_.Path -ceq $catalogRelPath })
    if ($catalogEntry.Count -ne 1) { throw ('The catalog was not found in the package: {0}' -f $catalogRelPath) }
    $catalogFull = $catalogEntry[0].FullName

    # 2. Catalog validation (on the file as the owner left it)
    $expectedCode = ''
    if ($null -ne $previous) { $expectedCode = [string]$previous.catalog.serverCode }
    $check = Test-CatalogFile -Sqlite3 $Sqlite3 -Db $catalogFull -ExpectedServerCode $expectedCode
    if ($check.Problems.Count -gt 0) { throw ("The catalog cannot be sealed:`n  " + ($check.Problems -join "`n  ")) }
    $meta = $check.Meta

    # Origin, product version, catalog change
    $catalogChanged = $false
    if ($null -ne $previous) { $catalogChanged = ([string]$previous.catalog.file -ceq $catalogRelPath) -and (@($previous.files | Where-Object { $_.path -ceq $catalogRelPath })[0].sha256 -cne $catalogEntry[0].Sha256) }
    $originValue = $ForcedOrigin
    $originRef = ''
    $productVersionValue = $Version
    if ($null -ne $previous) {
        if (-not $productVersionValue) { $productVersionValue = [string]$previous.productVersion }
        if (-not $originValue) { $originValue = $(if ($catalogChanged) { 'manual-edit-sealed' } else { [string]$previous.catalog.origin }) }
        if (-not $catalogChanged -and $originValue -ceq [string]$previous.catalog.origin -and $null -ne $previous.catalog.PSObject.Properties['originReference']) { $originRef = [string]$previous.catalog.originReference }
    }
    else {
        if (-not $productVersionValue) { throw 'The first seal needs -ProductVersion.' }
        if ($ConversionManifestPath) {
            if (-not (Test-Path -LiteralPath $ConversionManifestPath -PathType Leaf)) { throw 'The conversion manifest was not found.' }
            $conv = [System.IO.File]::ReadAllText($ConversionManifestPath) | ConvertFrom-Json -DateKind String
            $match = @($conv.catalogs | Where-Object { [string]$_.sha256 -ceq $catalogEntry[0].Sha256 })
            if ($match.Count -ne 1) { throw 'The catalog does not match any catalog of the conversion manifest (SHA-256 differs): it was changed after the conversion. Seal it as manual-edit-sealed instead.' }
            if (-not $originValue) { $originValue = 'conversion-tool' }
            $originRef = ('conversion run {0}' -f $conv.convertedAtUtc)
        }
        if (-not $originValue) { throw 'The first seal needs -ConversionManifest (the catalog must be the one the converter wrote) or an explicit -Origin.' }
    }
    if ($productVersionValue -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$') { throw 'The product version must be a semantic version.' }
    $builtAt = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($originValue -ceq 'manual-edit-sealed' -and -not $originRef) {
        $originRef = ('manual edit sealed {0}' -f $builtAt)
        if ($NoteText.Length -gt 0) { $originRef += ': ' + $NoteText }
    }
    if ($originRef.Length -gt 200) { $originRef = $originRef.Substring(0, 200) }

    # 3. Catalog meta on a temporary copy when the catalog was edited or its origin is restated
    $workDir = Join-Path ([System.IO.Path]::GetTempPath()) ('seal-work-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $backup = Join-Path $workDir 'catalog.original'
    $stagedCatalog = Join-Path $workDir 'catalog.staged'
    $replaced = $false
    try {
        Copy-Item -LiteralPath $catalogFull -Destination $backup
        Copy-Item -LiteralPath $catalogFull -Destination $stagedCatalog
        $metaChange = ($meta.SourceKind -cne $originValue)
        if ($catalogChanged -or $metaChange) {
            $sql = "UPDATE catalog_meta SET source_kind = '{0}', source_reference = '{1}', built_at_utc = '{2}' WHERE meta_id = 1;" -f $originValue, $originRef.Replace("'", "''"), $builtAt
            [void](Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @($stagedCatalog, $sql))
            $again = Test-CatalogFile -Sqlite3 $Sqlite3 -Db $stagedCatalog -ExpectedServerCode $meta.ServerCode
            if ($again.Problems.Count -gt 0) { throw ("The catalog is not valid after the meta update:`n  " + ($again.Problems -join "`n  ")) }
        }
        $stagedHash = Get-FileSha256Hex -Path $stagedCatalog
        $stagedBytes = (Get-Item -LiteralPath $stagedCatalog).Length

        # 4. Manifest
        $entries = foreach ($f in $scan.Files) {
            if ($f.Path -ceq $catalogRelPath) { [ordered]@{ path = $f.Path; sha256 = $stagedHash; size = [long]$stagedBytes } }
            else { [ordered]@{ path = $f.Path; sha256 = $f.Sha256; size = [long]$f.Bytes } }
        }
        $catalogBlock = [ordered]@{ serverCode = $meta.ServerCode; file = $catalogRelPath; schemaVersion = $meta.SchemaVersion; origin = $originValue }
        if ($originRef.Length -gt 0) { $catalogBlock['originReference'] = $originRef }
        $manifest = [ordered]@{
            contractVersion = $script:ContractVersion
            packageId       = [guid]::NewGuid().ToString('D').ToLowerInvariant()
            productVersion  = $productVersionValue
            builtAt         = $builtAt
            catalog         = $catalogBlock
            files           = @($entries)
        }

        # Summary
        $summary = [System.Collections.Generic.List[string]]::new()
        $summary.Add(('Package: {0}  version {1}  catalog for {2} (origin {3})' -f $root, $productVersionValue, $meta.ServerCode, $originValue))
        if ($null -eq $previous) { $summary.Add(('First seal: {0} file(s) will be listed.' -f @($entries).Count)) }
        else {
            $old = @{}
            foreach ($e in @($previous.files)) { $old[[string]$e.path] = [string]$e.sha256 }
            $new = @{}
            foreach ($e in @($entries)) { $new[[string]$e.path] = [string]$e.sha256 }
            $added = @($new.Keys | Where-Object { -not $old.ContainsKey($_) } | Sort-Object)
            $removed = @($old.Keys | Where-Object { -not $new.ContainsKey($_) } | Sort-Object)
            $changed = @($new.Keys | Where-Object { $old.ContainsKey($_) -and $old[$_] -cne $new[$_] } | Sort-Object)
            $summary.Add(('Files: {0} added, {1} removed, {2} changed, {3} unchanged.' -f $added.Count, $removed.Count, $changed.Count, (@($new.Keys).Count - $added.Count - $changed.Count)))
            foreach ($n in $added) { $summary.Add(('  added:   {0}' -f $n)) }
            foreach ($n in $removed) { $summary.Add(('  removed: {0}' -f $n)) }
            foreach ($n in $changed) { $summary.Add(('  changed: {0}' -f $n)) }
        }
        if ($catalogChanged -or $null -eq $previous) {
            if ($BaselineDb) {
                if (-not (Test-Path -LiteralPath $BaselineDb -PathType Leaf)) { throw 'The baseline catalog was not found.' }
                $a = Get-TableDigests -Sqlite3 $Sqlite3 -Db $BaselineDb
                $b = Get-TableDigests -Sqlite3 $Sqlite3 -Db $stagedCatalog
                $diff = [System.Collections.Generic.List[string]]::new()
                foreach ($t in ($b.Keys | Sort-Object)) {
                    if ($t -ceq 'catalog_meta') { continue }
                    if (-not $a.Contains($t)) { $diff.Add(('  table {0}: new ({1} row(s))' -f $t, $b[$t].Rows)) }
                    elseif ($a[$t].Digest -cne $b[$t].Digest) { $diff.Add(('  table {0}: content changed (rows {1} -> {2})' -f $t, $a[$t].Rows, $b[$t].Rows)) }
                }
                foreach ($t in ($a.Keys | Sort-Object)) { if ($t -cne 'catalog_meta' -and -not $b.Contains($t)) { $diff.Add(('  table {0}: removed' -f $t)) } }
                $summary.Add(('Catalog compared with the baseline: {0} table(s) differ.' -f $diff.Count))
                foreach ($d in $diff) { $summary.Add($d) }
            }
            elseif ($catalogChanged) { $summary.Add('Catalog changed since the last seal. No -Baseline was given, so which tables changed cannot be shown.') }
        }
        if ($catalogChanged -or $metaChange) { $summary.Add(('catalog_meta will record source_kind {0} and built_at_utc {1}.' -f $originValue, $builtAt)) }
        $summary.Add($(if ($AllowUnsigned -and -not $Signer) { 'SIGNATURE: none (-Unsigned). The application refuses this package unless started with its development flag.' } else { 'The manifest will be signed by the credential tool signer.' }))
        foreach ($line in $summary) { Write-Host $line }

        if ($Preview) {
            Write-Host 'Dry run: nothing was written.'
            return [pscustomobject]@{ Sealed = $false; Summary = $summary.ToArray(); PackageId = $manifest['packageId']; Manifest = $manifest }
        }
        if (-not $Confirmed) {
            if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { throw 'Confirmation is needed. Run it in a console, or pass -Yes.' }
            $answer = Read-Host 'Type SEAL to write the manifest'
            if ($answer -cne 'SEAL') { throw 'Not confirmed. Nothing was written.' }
        }

        # 5. Sign, then write
        $signed = $false
        if ($Signer) {
            $manifest['signature'] = Invoke-Signer -Script $Signer -Bytes (Get-CanonicalManifestBytes -Manifest $manifest)
            $signed = $true
        }
        $roundTrip = $manifest | ConvertTo-Json -Depth 8 -EscapeHandling EscapeNonAscii | ConvertFrom-Json -DateKind String
        $problems = @(Test-ManifestStructure -Manifest $roundTrip | Where-Object { $signed -or $_ -notlike 'The manifest has no "signature"*' })
        if ($problems.Count -gt 0) { throw ('The manifest built is not valid: {0}' -f ($problems -join ' ')) }
        if ($stagedHash -cne $catalogEntry[0].Sha256) { Copy-Item -LiteralPath $stagedCatalog -Destination $catalogFull -Force; $replaced = $true }
        Write-ManifestFile -Path $manifestPath -Manifest $manifest
        $replaced = $false

        if (-not $LogPath) { $LogPath = $root + '.seal.log' }
        $logLine = '{0} package={1} version={2} server={3} origin={4} files={5} {6}' -f $builtAt, $manifest['packageId'], $productVersionValue, $meta.ServerCode, $originValue, @($entries).Count, $(if ($signed) { 'signed' } else { 'UNSIGNED' })
        try { [System.IO.File]::AppendAllText($LogPath, $logLine + "`n") }
        catch { Write-Warning ('The seal log could not be written: {0}' -f $_.Exception.Message) }
        Write-Host ('Sealed. Manifest: {0}' -f $manifestPath)
        return [pscustomobject]@{ Sealed = $true; Summary = $summary.ToArray(); PackageId = $manifest['packageId']; Manifest = $manifest; ManifestPath = $manifestPath; LogPath = $LogPath }
    }
    catch {
        if ($replaced) { Copy-Item -LiteralPath $backup -Destination $catalogFull -Force }
        throw
    }
    finally { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($VerifyOnly) {
        $r = Invoke-PackageVerification -Folder $PackageFolder -Sqlite3 $Sqlite3Path -Verifier $VerifierScript
        foreach ($p in $r.Problems) { Write-Host ('FAIL  {0}' -f $p) }
        Write-Host ('Signature: {0}' -f $r.Signature)
        Write-Host ('{0}' -f $(if ($r.Ok) { 'The package matches its manifest.' } else { 'The package does NOT match its manifest.' }))
        if (-not $r.Ok) { exit 1 }
    }
    else {
        $null = Invoke-Seal -Folder $PackageFolder -Sqlite3 $Sqlite3Path -Signer $SignerScript -AllowUnsigned ([bool]$Unsigned) -Version $ProductVersion -CatalogRel $CatalogRelativePath -ConversionManifestPath $ConversionManifest -ForcedOrigin $Origin -BaselineDb $Baseline -NoteText $Note -LogPath $SealLog -Confirmed ([bool]$Yes) -Preview ([bool]$DryRun)
    }
}
