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
    # value. Fail closed for the two forms we can identify without ambiguity: PEM-style blocks
    # and assignments whose value starts on the following physical line. This runs before the
    # scalar assignment regex so block bodies cannot survive partial first-token replacement.
    $pemAssignmentPattern = '(?is)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]\s*(-----BEGIN [^\r\n]+-----.*?-----END [^\r\n]+-----)'
    $text = [regex]::Replace($text, $pemAssignmentPattern, '$1=[REDACTED]')

    $newlineAssignmentPattern = '(?is)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=][ \t]*(?:\r\n|\r|\n).*'
    $text = [regex]::Replace($text, $newlineAssignmentPattern, '$1=[REDACTED]')

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
