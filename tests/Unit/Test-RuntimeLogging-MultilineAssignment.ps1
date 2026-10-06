#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modulePath = Join-Path $repo 'runtime' 'Sisqual.Runtime.Logging.psm1'
Import-Module $modulePath -Force

$passed = 0
$failed = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:passed++; Write-Host "PASS  $Name" }
    else { $script:failed++; Write-Host "FAIL  $Name" }
}

$tempBase = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-log-multiline-' + [guid]::NewGuid().ToString('N'))
try {
    $privateRoot = Join-Path $tempBase 'private-key'
    Initialize-SisqualRuntimeLog -LogRoot $privateRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiAssign' | Out-Null
    $marker = 'PrivateKey' + 'MultilineLeakMarker'
    $pemBegin = '-----BEGIN ' + 'PRIVATE KEY-----'
    $pemEnd = '-----END ' + 'PRIVATE KEY-----'
    $message = "safe-prefix private_key=$pemBegin`n$marker`nMII-body`n$pemEnd safe-suffix"
    $path = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTIASSIGN' -Message $message -TimestampUtc ([datetime]'2026-10-06T08:00:00Z')
    $text = [IO.File]::ReadAllText($path)
    Check 'PEM-style private-key assignment is fully redacted' (($text -notmatch [regex]::Escape($marker)) -and ($text -notmatch 'MII-body') -and ($text -notmatch 'BEGIN PRIVATE KEY') -and ($text -match 'private_key=\[REDACTED\]'))
    Check 'safe prefix before PEM assignment remains available' ($text -match 'safe-prefix')
    Check 'PEM redaction remains one physical log record' (([IO.File]::ReadAllLines($path)).Count -eq 1)

    $credentialRoot = Join-Path $tempBase 'credential'
    Initialize-SisqualRuntimeLog -LogRoot $credentialRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiCredential' | Out-Null
    $credentialMarker = 'Credential' + 'MultilineLeakMarker'
    $credentialMessage = "safe-prefix credential=`n$credentialMarker`ncontinuation-body"
    $credentialPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTICREDENTIAL' -Message $credentialMessage -TimestampUtc ([datetime]'2026-10-06T08:00:00Z')
    $credentialText = [IO.File]::ReadAllText($credentialPath)
    Check 'newline-start credential assignment is fail-closed' (($credentialText -notmatch [regex]::Escape($credentialMarker)) -and ($credentialText -notmatch 'continuation-body') -and ($credentialText -match 'credential=\[REDACTED\]'))
    Check 'safe prefix before multiline credential remains available' ($credentialText -match 'safe-prefix')
    Check 'credential redaction remains one physical log record' (([IO.File]::ReadAllLines($credentialPath)).Count -eq 1)

    $continuationRoot = Join-Path $tempBase 'same-line-continuation'
    Initialize-SisqualRuntimeLog -LogRoot $continuationRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiContinuation' | Out-Null
    $continuationMarker = 'SameLine' + 'ContinuationLeakMarker'
    $continuationMessage = "safe-prefix credential=first-line`r`n$continuationMarker`nsecond-secret"
    $continuationPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTICONTINUATION' -Message $continuationMessage -TimestampUtc ([datetime]'2026-10-06T08:00:00Z')
    $continuationText = [IO.File]::ReadAllText($continuationPath)
    Check 'same-line sensitive assignment continuation is fail-closed' (($continuationText -notmatch [regex]::Escape($continuationMarker)) -and ($continuationText -notmatch 'second-secret') -and ($continuationText -match 'credential=\[REDACTED\]'))
    Check 'safe prefix before same-line continuation remains available' ($continuationText -match 'safe-prefix')
    Check 'same-line continuation redaction remains one physical log record' (([IO.File]::ReadAllLines($continuationPath)).Count -eq 1)

    $whitespaceRoot = Join-Path $tempBase 'whitespace-continuation'
    Initialize-SisqualRuntimeLog -LogRoot $whitespaceRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiWhitespace' | Out-Null
    $whitespaceMarker = 'Whitespace' + 'ContinuationLeakMarker'
    $whitespaceMessage = "safe-prefix credential=first part`r`n$whitespaceMarker`nsecond-secret"
    $whitespacePath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTIWHITESPACE' -Message $whitespaceMessage -TimestampUtc ([datetime]'2026-10-06T08:00:00Z')
    $whitespaceText = [IO.File]::ReadAllText($whitespacePath)
    Check 'whitespace-bearing multiline credential is fail-closed' (($whitespaceText -notmatch [regex]::Escape($whitespaceMarker)) -and ($whitespaceText -notmatch 'first part') -and ($whitespaceText -notmatch 'second-secret') -and ($whitespaceText -match 'credential=\[REDACTED\]'))
    Check 'safe prefix before whitespace multiline credential remains available' ($whitespaceText -match 'safe-prefix')
    Check 'whitespace multiline redaction remains one physical log record' (([IO.File]::ReadAllLines($whitespacePath)).Count -eq 1)

    $boundaryRoot = Join-Path $tempBase 'same-line-boundary'
    Initialize-SisqualRuntimeLog -LogRoot $boundaryRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiBoundary' | Out-Null
    $boundaryMarker = 'Boundary' + 'ContinuationLeakMarker'
    $secondName = 'pass' + 'word'
    $boundaryMessage = "safe-prefix credential=first part $secondName=second-value`r`n$boundaryMarker`ncontinuation-body"
    $boundaryPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTIBOUNDARY' -Message $boundaryMessage -TimestampUtc ([datetime]'2026-10-06T08:00:00Z')
    $boundaryText = [IO.File]::ReadAllText($boundaryPath)
    Check 'same-line sensitive boundary does not leak the preceding whitespace value' (($boundaryText -notmatch 'first part') -and ($boundaryText -notmatch 'second-value') -and ($boundaryText -notmatch [regex]::Escape($boundaryMarker)) -and ($boundaryText -notmatch 'continuation-body'))
    Check 'same-line sensitive fields remain independently redacted' (($boundaryText -match 'credential=\[REDACTED\]') -and ($boundaryText -match ([regex]::Escape($secondName) + '=\[REDACTED\]')))
    Check 'safe prefix before same-line sensitive boundary remains available' ($boundaryText -match 'safe-prefix')
    Check 'same-line boundary redaction remains one physical log record' (([IO.File]::ReadAllLines($boundaryPath)).Count -eq 1)
}
finally {
    Remove-Module Sisqual.Runtime.Logging -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempBase) { Remove-Item -LiteralPath $tempBase -Recurse -Force }
}

Write-Host ('{0} passed, {1} failed' -f $passed, $failed)
if ($failed -gt 0) { exit 1 }
