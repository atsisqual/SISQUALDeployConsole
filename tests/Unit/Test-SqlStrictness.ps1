#requires -Version 7.0
<#
.SYNOPSIS
    Static check: SQL text in the tools and tests must not use double quotes around a text value.

.DESCRIPTION
    SQLite reads "x" as an identifier. The Linux sqlite3 builds used for local work still accept an
    unknown "x" as a string (a legacy fallback), but the pinned Windows sqlite3 (3.53.4) does not:
    it answers 'no such column'. A defect of this kind passed every Linux run and failed only in CI
    on Windows (Test-CatalogConversion.ps1, PR #21). Text values must use single quotes; double
    quotes are only for identifiers.

    The check looks at every line of tools/ and tests/ that contains SELECT, WHERE, INSERT or PRAGMA
    and a double-quoted run of 1 or 2 punctuation characters directly next to the SQL concatenation
    operator ||, which is how this mistake looks (a separator joined into a result). It is a
    heuristic, not a SQL parser; other forms of the same mistake are not caught by it.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'tools'), (Join-Path $repo 'tests') -Recurse -File -Filter '*.ps1' | Where-Object { $_.Name -ne 'Test-SqlStrictness.ps1' })
$hits = [System.Collections.Generic.List[string]]::new()
# "x" next to ||, where x is 1 or 2 non-word, non-space characters; the quotes may be escaped (\" or `")
$q = '[`\\]?"'
$punct = '[^\w\s"`\\]{1,2}'
$pattern = '\|\|\s*' + $q + $punct + $q + '|' + $q + $punct + $q + '\s*\|\|'
foreach ($file in $files) {
    $lineNo = 0
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        $lineNo++
        if ($line -notmatch '(?i)\b(SELECT|WHERE|INSERT|PRAGMA)\b') { continue }
        if ($line -match $pattern) { $hits.Add(('{0}:{1}' -f $file.FullName.Substring($repo.Length + 1), $lineNo)) }
    }
}

# The check must itself work: a known bad line is flagged, a known good one is not.
$bad = 'SELECT a || "|" || b FROM t;'
$good = "SELECT a || '|' || b FROM t;"
$selfOk = ($bad -match $pattern) -and -not ($good -match $pattern) -and -not ('x.Replace("''", "''''")' -match $pattern)
Write-Host ('{0}  the heuristic flags a double-quoted separator and accepts a single-quoted one' -f $(if ($selfOk) { 'PASS' } else { 'FAIL' }))
Write-Host ('{0}  no SQL text with a double-quoted separator in {1} files{2}' -f $(if ($hits.Count -eq 0) { 'PASS' } else { 'FAIL' }), $files.Count, $(if ($hits.Count -gt 0) { ': ' + ($hits -join ', ') } else { '' }))
$failures = 0
if (-not $selfOk) { $failures++ }
if ($hits.Count -gt 0) { $failures++ }
Write-Host ('{0} passed, {1} failed' -f (2 - $failures), $failures)
if ($failures -gt 0) { exit 1 }
