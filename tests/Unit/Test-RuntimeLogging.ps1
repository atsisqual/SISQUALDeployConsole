#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modulePath = Join-Path $repo 'runtime' 'Sisqual.Runtime.Logging.psm1'
Import-Module $modulePath -Force

$script:Passed = 0
$script:Failed = 0

function Test-Check {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [bool]$Condition
    )

    if ($Condition) {
        $script:Passed++
        Write-Host "PASS  $Name"
    }
    else {
        $script:Failed++
        Write-Host "FAIL  $Name"
    }
}

function Test-Throws {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    Test-Check -Name $Name -Condition $threw
}

$defaults = Get-SisqualRuntimeLogDefaults
Test-Check 'default approved root is the SISQUAL log tree' ($defaults.ApprovedRoot -ceq 'C:\SISQUALWFM\WFM.Logs')
Test-Check 'default log root matches ADR-0007' ($defaults.LogRoot -ceq 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement')
Test-Check 'default retention is 30 days' ($defaults.RetentionDays -eq 30)
Test-Check 'default prefix is stable' ($defaults.Prefix -ceq 'SISQUALDeployConsole')

$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-approved-' + [guid]::NewGuid().ToString('N'))
$tempRoot = Join-Path $tempBase 'console'
$outsideRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-outside-' + [guid]::NewGuid().ToString('N'))
try {
    Test-Throws 'log root outside approved root is rejected' {
        Initialize-SisqualRuntimeLog -LogRoot $outsideRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'TestLog' | Out-Null
    }
    Test-Throws 'UNC approved root is rejected' {
        Initialize-SisqualRuntimeLog -LogRoot '\\server\share\console' -ApprovedRoot '\\server\share' -RetentionDays 3 -Prefix 'TestLog' | Out-Null
    }

    $state = Initialize-SisqualRuntimeLog -LogRoot $tempRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'TestLog'
    Test-Check 'initialize creates configured directory' (Test-Path -LiteralPath $tempRoot -PathType Container)
    Test-Check 'initialize returns canonical approved root' ($state.ApprovedRoot -ceq [System.IO.Path]::GetFullPath($tempBase))
    Test-Check 'initialize returns canonical log root' ($state.LogRoot -ceq [System.IO.Path]::GetFullPath($tempRoot))
    Test-Check 'initialize returns configured retention' ($state.RetentionDays -eq 3)

    $reference = [datetime]::SpecifyKind([datetime]'2026-10-06T12:00:00', [DateTimeKind]::Utc)
    $oldPath = Join-Path $tempRoot 'TestLog-2026-10-03.log'
    $boundaryPath = Join-Path $tempRoot 'TestLog-2026-10-04.log'
    $foreignPath = Join-Path $tempRoot 'Other-2020-01-01.log'
    [IO.File]::WriteAllText($oldPath, 'old')
    [IO.File]::WriteAllText($boundaryPath, 'keep')
    [IO.File]::WriteAllText($foreignPath, 'foreign')

    $removed = Invoke-SisqualRuntimeLogRetention -ReferenceUtc $reference
    Test-Check 'retention removes files older than the configured window' ($removed -eq 1 -and -not (Test-Path -LiteralPath $oldPath))
    Test-Check 'retention keeps the exact UTC boundary day' (Test-Path -LiteralPath $boundaryPath)
    Test-Check 'retention ignores files outside the logger prefix' (Test-Path -LiteralPath $foreignPath)

    $passwordKey = 'Pass' + 'word'
    $passwordValue = 'Top' + 'Secret'
    $jsonMarker = 'Json' + 'Marker'
    $basicMarker = 'dXNl' + 'cjpwYXNz'
    $jsonPayload = '{"' + $passwordKey + '":"' + $jsonMarker + '"}'
    $message = "Starting token=abc123 Bearer xyz Authorization: Basic $basicMarker`n$jsonPayload"
    $properties = [ordered]@{
        Instance = 'DEMOES'
        Note = 'authorization=BasicValue'
        Cookie = 'session-cookie-value'
    }
    $properties[$passwordKey] = $passwordValue

    $logPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.START' -Message $message -Properties $properties -TimestampUtc $reference
    $text = [IO.File]::ReadAllText($logPath)
    Test-Check 'write creates the expected daily log file' ([IO.Path]::GetFileName($logPath) -ceq 'TestLog-2026-10-06.log')
    Test-Check 'write keeps safe context' ($text -match 'Instance="DEMOES"')
    $passwordRedactionPattern = [regex]::Escape($passwordKey) + '="\[REDACTED\]"'
    Test-Check 'write redacts sensitive property names' ($text -match $passwordRedactionPattern -and $text -match 'Cookie="\[REDACTED\]"')
    Test-Check 'write redacts token and authorization assignments' ($text -match 'token=\[REDACTED\]' -and $text -match 'authorization=\[REDACTED\]')
    Test-Check 'write redacts bearer credentials' ($text -match 'Bearer \[REDACTED\]')
    $authorizationRedactionPattern = '(?i)authorization\s*(?::|=)\s*\[REDACTED\]'
    Test-Check 'write redacts complete Basic authorization header value' (($text -match $authorizationRedactionPattern) -and ($text -notmatch [regex]::Escape($basicMarker)))
    Test-Check 'write redacts quoted sensitive JSON keys' ($text -match ([regex]::Escape($passwordKey) + '=\[REDACTED\]'))
    $forbidden = 'abc123|' + [regex]::Escape($passwordValue) + '|BasicValue|session-cookie-value|Bearer xyz|' + [regex]::Escape($basicMarker) + '|' + [regex]::Escape($jsonMarker)
    Test-Check 'write does not contain supplied secret markers' ($text -notmatch $forbidden)
    Test-Check 'write normalizes embedded newlines to one physical record' (([IO.File]::ReadAllLines($logPath)).Count -eq 1)

    $bytes = [IO.File]::ReadAllBytes($logPath)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Test-Check 'log is UTF-8 without BOM' (-not $hasUtf8Bom)

    Test-Check 'rollover fixture exists before next UTC day' (Test-Path -LiteralPath $boundaryPath)
    $nextDay = $reference.AddDays(1)
    $nextPath = Write-SisqualRuntimeLog -Level WARN -EventCode 'RUNTIME.NEXTDAY' -Message 'next' -TimestampUtc $nextDay
    Test-Check 'daily rotation chooses a new file by UTC day' ([IO.Path]::GetFileName($nextPath) -ceq 'TestLog-2026-10-07.log')
    Test-Check 'daily rollover re-runs retention' (-not (Test-Path -LiteralPath $boundaryPath))

    Test-Throws 'invalid event codes are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'bad event' -Message 'x' | Out-Null }
    Test-Throws 'unsafe property names are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.BADFIELD' -Message 'x' -Properties @{ 'bad field' = 'value' } | Out-Null }
}
finally {
    Remove-Module Sisqual.Runtime.Logging -ErrorAction SilentlyContinue
    foreach ($path in @($tempBase, $outsideRoot)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) {
    exit 1
}
