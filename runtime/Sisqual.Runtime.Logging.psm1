#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Keep the reviewed filesystem/retention implementation byte-identical in the core file.
# This wrapper only hardens free-form sensitive assignment redaction.
. (Join-Path $PSScriptRoot 'Sisqual.Runtime.Logging.Core.ps1')

function Protect-SisqualRuntimeLogText {
    param(
        [AllowNull()]
        [object]$Value
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }

    $headerPattern = '(?i)\b(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*[^\r\n]*(?:(?:\r\n|\r|\n)[ \t]+[^\r\n]*)*'
    $text = [regex]::Replace($text, $headerPattern, '$1: [REDACTED]')
    $text = [regex]::Replace($text, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', '$1 [REDACTED]')

    $sensitiveNamePattern = 'password|passwd|pwd|secret|token|credential|private.?key|client.?secret|authorization|cookie|api.?key|connection.?string'

    # Free-form log text has no general grammar that can reliably delimit an unquoted multiline
    # value. Fail closed for complete PEM blocks first.
    $pemAssignmentPattern = '(?is)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]\s*(-----BEGIN [^\r\n]+-----.*?-----END [^\r\n]+-----)'
    $text = [regex]::Replace($text, $pemAssignmentPattern, '$1=[REDACTED]')

    # Free-form unquoted sensitive assignments are ambiguous once whitespace or a physical newline
    # is present. Scan the remainder of the physical line for a recognized independent sensitive
    # field/header boundary. When one exists, redact only up to that boundary and continue from it.
    # Otherwise fail closed: whitespace/newline-bearing values consume the remainder of the input.
    # A compact single-token value with no whitespace/newline is left for the scalar fallback below.
    $unquotedCandidatePattern = '(?i)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=][ \t]*(?!["''])(?<line>[^\r\n]*)(?<newline>\r\n|\r|\n|\z)'
    $sameLineBoundaryPattern = '(?i)\b(Bearer|Basic)\s+|\b(authorization|proxy-authorization|cookie|set-cookie)\s*:|(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]'
    $unquotedCandidateRegex = [regex]::new($unquotedCandidatePattern)
    $sameLineBoundaryRegex = [regex]::new($sameLineBoundaryPattern)
    $scanIndex = 0
    while ($scanIndex -lt $text.Length) {
        $candidate = $unquotedCandidateRegex.Match($text, $scanIndex)
        if (-not $candidate.Success) {
            break
        }

        $sameLineValue = [string]$candidate.Groups['line'].Value
        $trimmedValue = $sameLineValue.Trim()
        if ($trimmedValue.StartsWith('[REDACTED]', [StringComparison]::Ordinal)) {
            $nextIndex = $candidate.Groups['line'].Index + [Math]::Min($sameLineValue.Length, '[REDACTED]'.Length)
            if ($nextIndex -le $scanIndex) {
                $nextIndex = $candidate.Index + [Math]::Max($candidate.Length, 1)
            }
            $scanIndex = $nextIndex
            continue
        }

        $boundary = $sameLineBoundaryRegex.Match($sameLineValue)
        if ($boundary.Success) {
            $boundaryIndex = $candidate.Groups['line'].Index + $boundary.Index
            $replacement = $candidate.Groups[1].Value + '=[REDACTED] '
            $text = $text.Substring(0, $candidate.Index) + $replacement + $text.Substring($boundaryIndex)
            $scanIndex = $candidate.Index + $replacement.Length
            continue
        }

        $hasPhysicalNewline = $candidate.Groups['newline'].Length -gt 0
        $hasWhitespace = $sameLineValue -match '[ \t]'
        if ($hasPhysicalNewline -or $hasWhitespace) {
            $text = $text.Substring(0, $candidate.Index) + $candidate.Groups[1].Value + '=[REDACTED]'
            break
        }

        $scanIndex = $candidate.Index + [Math]::Max($candidate.Length, 1)
    }

    # Decode JSON property-name escapes before deciding whether the field is sensitive. Once a
    # sensitive serialized key is found, conservatively redact the remainder of the field so
    # scalar, escaped, composite and multiline values cannot leak through regex edge cases.
    $jsonPropertyPattern = '"(?<key>(?:\\.|[^"\\])*)"\s*:'
    foreach ($jsonProperty in @([regex]::Matches($text, $jsonPropertyPattern))) {
        $jsonDocument = $null
        $decodedKey = $null
        try {
            $encodedKey = '"' + $jsonProperty.Groups['key'].Value + '"'
            $jsonDocument = [System.Text.Json.JsonDocument]::Parse([string]$encodedKey)
            $decodedKey = [string]$jsonDocument.RootElement.GetString()
        }
        catch {
            $decodedKey = $null
        }
        finally {
            if ($null -ne $jsonDocument) {
                $jsonDocument.Dispose()
            }
        }

        if (-not [string]::IsNullOrEmpty($decodedKey) -and (Test-SisqualSensitiveLogField -Name $decodedKey)) {
            $text = $text.Substring(0, $jsonProperty.Index) + $decodedKey + '=[REDACTED]'
            break
        }
    }

    $doubleQuotedValue = '"(?:\\.|[^"\\])*"'
    $singleQuotedValue = '''(?:\\.|[^''\\])*'''
    $assignmentPattern = '(?i)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]\s*(' + $doubleQuotedValue + '|' + $singleQuotedValue + '|[^\s,;}\]]+)'
    $text = [regex]::Replace($text, $assignmentPattern, '$1=[REDACTED]')

    $text = $text -replace "`r`n|`r|`n", '\n'
    return $text
}
