#requires -Version 7.0
<#
.SYNOPSIS
    Exports the engine scripts stored in ops.Engine to plain files, plus a manifest.

.DESCRIPTION
    Step B1 of docs/migration/catalog-conversion-plan.md (section 5.4).
    The exported files are only the base for the engine ports. They are NOT part of
    the repository and NOT part of the portable application, they are never executed
    by this tool, and they are never copied into a catalog (R-027).

    Two sources:
      -SyncFile    reads a ManagementSync.sql file (offline, read only).
      -SqlInstance reads ops.Engine from SQL Server with Microsoft.Data.SqlClient,
                   read only (ApplicationIntent=ReadOnly, integrated security).
                   [V] not tested against a real server.

    For each engine the tool writes <SourceFileName> as UTF-8 without BOM, keeping the
    text byte-for-byte as stored (CRLF is kept), and checks that the SHA-256 of the
    UTF-16LE text equals the stored ScriptSha256. The manifest records both hashes,
    the line ending style, whether the text is ASCII, and secret-pattern hit COUNTS.
    Secret values are never printed or written.

    The output folder must be outside the repository (the files are not ASCII-only and
    use CRLF, which the repository policy forbids).
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

    [Parameter(Mandatory)]
    [string]$OutputFolder,

    [string[]]$EngineCode,

    [switch]$AllowMismatch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolVersion = '0.1.0'
$script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# ---------------------------------------------------------------------------
# SQL text parsing (offline source)
# ---------------------------------------------------------------------------

function Read-SqlNLiteral {
    # Reads N'...' starting at $Position. Returns the unescaped value and the next position.
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][int]$Position
    )
    if ($Position + 1 -ge $Text.Length -or $Text[$Position] -ne 'N' -or $Text[$Position + 1] -ne "'") {
        throw ('Expected N-prefixed string literal at offset {0}.' -f $Position)
    }
    $start = $Position + 2
    $builder = [System.Text.StringBuilder]::new()
    while ($true) {
        $quote = $Text.IndexOf("'", $start, [System.StringComparison]::Ordinal)
        if ($quote -lt 0) { throw 'Unterminated string literal.' }
        [void]$builder.Append($Text, $start, $quote - $start)
        if ($quote + 1 -lt $Text.Length -and $Text[$quote + 1] -eq "'") {
            [void]$builder.Append("'")
            $start = $quote + 2
            continue
        }
        return [pscustomobject]@{ Value = $builder.ToString(); Next = $quote + 1 }
    }
}

function Skip-SqlSeparator {
    param([string]$Text, [int]$Position)
    if ($Text.Substring($Position, 2) -ne ', ') {
        throw ('Expected a comma separator at offset {0}.' -f $Position)
    }
    return $Position + 2
}

function Read-SqlSimpleToken {
    # Reads a non-string token (number, bit, date literal, NULL) up to the next top-level comma or ')'.
    param([string]$Text, [int]$Position)
    $i = $Position
    $depth = 0
    $inQuote = $false
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($inQuote) {
            if ($c -eq "'") {
                if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "'") { $i++ } else { $inQuote = $false }
            }
        }
        elseif ($c -eq "'") { $inQuote = $true }
        elseif ($c -eq '(') { $depth++ }
        elseif ($c -eq ')') {
            if ($depth -eq 0) { break }
            $depth--
        }
        elseif ($c -eq ',' -and $depth -eq 0) { break }
        $i++
    }
    return [pscustomobject]@{ Value = $Text.Substring($Position, $i - $Position).Trim(); Next = $i }
}

function Read-EnginesFromSyncText {
    param([Parameter(Mandatory)][string]$Text)

    $marker = 'INSERT INTO [ops].[Engine] ([EngineCode], [DisplayName], [SourceFileName], [EngineVersion], [ScriptText], [ScriptSha256], [MinimumPowerShell], [RequiresAdministrator], [IsEnabled], [ModifiedAt]) VALUES ('
    $engines = [System.Collections.Generic.List[object]]::new()
    $from = 0
    while ($true) {
        $at = $Text.IndexOf($marker, $from, [System.StringComparison]::Ordinal)
        if ($at -lt 0) { break }
        $pos = $at + $marker.Length

        $r = Read-SqlNLiteral -Text $Text -Position $pos; $code = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $display = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $fileName = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $version = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $script = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $sha = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlNLiteral -Text $Text -Position $pos; $minPs = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlSimpleToken -Text $Text -Position $pos; $admin = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlSimpleToken -Text $Text -Position $pos; $enabled = $r.Value; $pos = Skip-SqlSeparator $Text $r.Next
        $r = Read-SqlSimpleToken -Text $Text -Position $pos; $modified = $r.Value.Trim("'"); $pos = $r.Next

        $engines.Add([pscustomobject]@{
                EngineCode            = $code
                DisplayName           = $display
                SourceFileName        = $fileName
                EngineVersion         = $version
                ScriptText            = $script
                ScriptSha256          = $sha
                MinimumPowerShell     = $minPs
                RequiresAdministrator = ($admin -eq '1')
                IsEnabled             = ($enabled -eq '1')
                ModifiedAt            = $modified
            })
        $from = $pos
    }
    return , $engines.ToArray()
}

function Read-EnginesFromSqlServer {
    param(
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$DatabaseName,
        [Parameter(Mandatory)][string]$ClientPath
    )
    $dll = $ClientPath
    if (Test-Path -LiteralPath $ClientPath -PathType Container) {
        $dll = Join-Path $ClientPath 'Microsoft.Data.SqlClient.dll'
    }
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        throw ('Microsoft.Data.SqlClient.dll was not found at: {0}' -f $dll)
    }
    Add-Type -Path $dll

    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Instance
    $builder['Initial Catalog'] = $DatabaseName
    $builder['Integrated Security'] = $true
    $builder['Application Intent'] = [Microsoft.Data.SqlClient.ApplicationIntent]::ReadOnly
    $builder['Application Name'] = 'Export-ManagementEngines'

    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    $engines = [System.Collections.Generic.List[object]]::new()
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT EngineCode, DisplayName, SourceFileName, EngineVersion, ScriptText, ScriptSha256, MinimumPowerShell, RequiresAdministrator, IsEnabled, ModifiedAt FROM ops.Engine ORDER BY EngineCode;'
        $command.CommandTimeout = 120
        $reader = $command.ExecuteReader()
        try {
            while ($reader.Read()) {
                $engines.Add([pscustomobject]@{
                        EngineCode            = [string]$reader['EngineCode']
                        DisplayName           = [string]$reader['DisplayName']
                        SourceFileName        = [string]$reader['SourceFileName']
                        EngineVersion         = [string]$reader['EngineVersion']
                        ScriptText            = [string]$reader['ScriptText']
                        ScriptSha256          = ([string]$reader['ScriptSha256']).Trim()
                        MinimumPowerShell     = [string]$reader['MinimumPowerShell']
                        RequiresAdministrator = [bool]$reader['RequiresAdministrator']
                        IsEnabled             = [bool]$reader['IsEnabled']
                        ModifiedAt            = ([datetime]$reader['ModifiedAt']).ToString('yyyy-MM-dd HH:mm:ss.fffffff')
                    })
            }
        }
        finally { $reader.Dispose() }
    }
    finally { $connection.Dispose() }
    return , $engines.ToArray()
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

function Get-Sha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '') }
    finally { $sha.Dispose() }
}

function Get-ScriptTextHash {
    # The stored ScriptSha256 is the SHA-256 of the UTF-16LE text (confirmed, PR #12).
    param([Parameter(Mandatory)][string]$Text)
    return Get-Sha256Hex -Bytes ([System.Text.Encoding]::Unicode.GetBytes($Text))
}

function Get-LineEndingStyle {
    param([string]$Text)
    $crlf = [regex]::Matches($Text, "`r`n").Count
    $lf = [regex]::Matches($Text, "(?<!`r)`n").Count
    if ($crlf -gt 0 -and $lf -eq 0) { return 'CRLF' }
    if ($crlf -eq 0 -and $lf -gt 0) { return 'LF' }
    if ($crlf -eq 0 -and $lf -eq 0) { return 'NONE' }
    return 'MIXED'
}

function Get-SecretPatternCounts {
    # Counts only. A hit is a literal value after password/secret/token/key words,
    # or a connection string that carries a user and password. Values are never kept.
    param([string]$Text)
    # A literal value does not start with a type cast '[' or a variable/placeholder char.
    $literal = '[^\s''",;\\{$%<)\[][^\s''",;\\{$%<)]{5,}'
    $patterns = [ordered]@{
        passwordLiteral   = '(?i)\b(password|pwd|passwd)\s*[=:]\s*' + $literal
        secretLiteral     = '(?i)\b(secret|apikey|api_key|token)\s*[=:]\s*' + $literal
        connectionUserAndSecret = '(?i)User ID\s*=\s*[^;]+;\s*Password\s*='
        privateKeyBlock   = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    }
    $result = [ordered]@{}
    foreach ($name in $patterns.Keys) {
        $result[$name] = [regex]::Matches($Text, $patterns[$name]).Count
    }
    return $result
}

function Test-SafeLeafName {
    param([string]$Name)
    return ($Name -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,100}\.ps1$')
}

function Test-PathInsideFolder {
    param([string]$Path, [string]$Folder)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $root = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    $cmp = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
    if ($full.Equals($root, $cmp)) { return $true }
    return $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, $cmp)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Invoke-EngineExport {
    param(
        [Parameter(Mandatory)][object[]]$Engines,
        [Parameter(Mandatory)][string]$Folder,
        [string[]]$Only,
        [hashtable]$SourceInfo,
        [switch]$AllowHashMismatch
    )

    if (Test-PathInsideFolder -Path $Folder -Folder $script:RepoRoot) {
        throw 'The output folder is inside the repository. Choose a folder outside it: the exported scripts are not ASCII-only and use CRLF.'
    }
    New-Item -ItemType Directory -Path $Folder -Force | Out-Null

    $selected = @($Engines)
    if ($Only -and $Only.Count -gt 0) {
        $selected = @($Engines | Where-Object { $Only -contains $_.EngineCode })
        $known = @($Engines | ForEach-Object { $_.EngineCode })
        $missing = @($Only | Where-Object { $known -notcontains $_ })
        if ($missing.Count -gt 0) { throw ('Engine code not found: {0}' -f ($missing -join ', ')) }
    }
    if ($selected.Count -eq 0) { throw 'No engine rows were found in the source.' }

    $names = @{}
    $entries = [System.Collections.Generic.List[object]]::new()
    $mismatches = 0
    foreach ($engine in $selected) {
        if (-not (Test-SafeLeafName $engine.SourceFileName)) {
            throw ('Unsafe SourceFileName for engine {0}.' -f $engine.EngineCode)
        }
        $key = $engine.SourceFileName.ToLowerInvariant()
        if ($names.ContainsKey($key)) { throw ('Two engines share the file name {0}.' -f $engine.SourceFileName) }
        $names[$key] = $true

        $computed = Get-ScriptTextHash -Text $engine.ScriptText
        $stored = ([string]$engine.ScriptSha256).Trim().ToUpperInvariant()
        $match = ($computed -eq $stored)
        if (-not $match) { $mismatches++ }

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $bytes = $utf8.GetBytes($engine.ScriptText)
        $target = Join-Path $Folder $engine.SourceFileName
        if ($match -or $AllowHashMismatch) {
            [System.IO.File]::WriteAllBytes($target, $bytes)
        }

        $nonAscii = ($engine.ScriptText.ToCharArray() | Where-Object { [int]$_ -gt 127 } | Measure-Object).Count
        $entries.Add([ordered]@{
                engineCode            = $engine.EngineCode
                displayName           = $engine.DisplayName
                engineVersion         = $engine.EngineVersion
                sourceFileName        = $engine.SourceFileName
                minimumPowerShell     = $engine.MinimumPowerShell
                requiresAdministrator = [bool]$engine.RequiresAdministrator
                isEnabled             = [bool]$engine.IsEnabled
                modifiedAt            = $engine.ModifiedAt
                storedScriptSha256    = $stored
                computedScriptSha256  = $computed
                hashMatches           = $match
                exportedFileWritten   = ($match -or [bool]$AllowHashMismatch)
                exportedFileSha256    = (Get-Sha256Hex -Bytes $bytes)
                exportedFileBytes     = $bytes.Length
                textCharacters        = $engine.ScriptText.Length
                lineEndings           = (Get-LineEndingStyle -Text $engine.ScriptText)
                nonAsciiCharacters    = [int]$nonAscii
                secretPatternHits     = (Get-SecretPatternCounts -Text $engine.ScriptText)
            })
    }

    $manifest = [ordered]@{
        contractVersion = '0.1-proposed'
        tool            = 'Export-ManagementEngines'
        toolVersion     = $script:ToolVersion
        exportedAtUtc   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        source          = $SourceInfo
        notes           = @(
            'Files are UTF-8 without BOM with the text exactly as stored (CRLF kept).',
            'storedScriptSha256 is compared with the SHA-256 of the UTF-16LE text.',
            'secretPatternHits are counts only; values are never recorded.',
            'These files are the base for the engine ports; they are not part of the repository, the portable application or any catalog.'
        )
        engineCount     = $entries.Count
        hashMismatches  = $mismatches
        engines         = $entries.ToArray()
    }
    $json = $manifest | ConvertTo-Json -Depth 8 -EscapeHandling EscapeNonAscii
    $json = ($json -replace "`r`n", "`n") + "`n"
    $manifestPath = Join-Path $Folder 'engines-export-manifest.json'
    [System.IO.File]::WriteAllBytes($manifestPath, [System.Text.UTF8Encoding]::new($false).GetBytes($json))

    if ($mismatches -gt 0 -and -not $AllowHashMismatch) {
        throw ('{0} engine(s) failed the stored-hash check; their files were not written. See {1}.' -f $mismatches, $manifestPath)
    }
    return [pscustomobject]@{ ManifestPath = $manifestPath; Engines = $entries.Count; Mismatches = $mismatches }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($PSCmdlet.ParameterSetName -eq 'Sync') {
        $resolved = (Resolve-Path -LiteralPath $SyncFile).Path
        $item = Get-Item -LiteralPath $resolved
        Write-Host ('Reading {0} ({1} bytes)...' -f $item.Name, $item.Length)
        $text = [System.IO.File]::ReadAllText($resolved, [System.Text.UTF8Encoding]::new($false))
        $engines = Read-EnginesFromSyncText -Text $text
        $info = [ordered]@{
            kind        = 'sync-file'
            fileName    = $item.Name
            fileBytes   = $item.Length
            fileSha256  = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
        }
    }
    else {
        $engines = Read-EnginesFromSqlServer -Instance $SqlInstance -DatabaseName $Database -ClientPath $SqlClientPath
        $info = [ordered]@{ kind = 'sql-server'; instance = $SqlInstance; database = $Database; readOnly = $true }
    }
    $summary = Invoke-EngineExport -Engines $engines -Folder $OutputFolder -Only $EngineCode -SourceInfo $info -AllowHashMismatch:$AllowMismatch
    Write-Host ('Exported {0} engine(s). Hash mismatches: {1}. Manifest: {2}' -f $summary.Engines, $summary.Mismatches, $summary.ManifestPath)
}
