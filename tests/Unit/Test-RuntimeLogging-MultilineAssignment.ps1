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
    $message = "safe-prefix private_key=-----BEGIN PRIVATE KEY-----`n$marker`nMII-body`n-----END PRIVATE KEY----- safe-suffix"
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
}
finally {
    Remove-Module Sisqual.Runtime.Logging -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempBase) { Remove-Item -LiteralPath $tempBase -Recurse -Force }
}

Write-Host ('{0} passed, {1} failed' -f $passed, $failed)
if ($failed -gt 0) { exit 1 }
