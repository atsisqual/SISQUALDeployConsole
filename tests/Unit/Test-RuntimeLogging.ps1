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
Test-Check 'default log root matches ADR-0007' ($defaults.LogRoot -ceq 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement')
Test-Check 'default retention is 30 days' ($defaults.RetentionDays -eq 30)
Test-Check 'default prefix is stable' ($defaults.Prefix -ceq 'SISQUALDeployConsole')

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-log-' + [guid]::NewGuid().ToString('N'))
try {
    $state = Initialize-SisqualRuntimeLog -LogRoot $tempRoot -RetentionDays 3 -Prefix 'TestLog'
    Test-Check 'initialize creates configured directory' (Test-Path -LiteralPath $tempRoot -PathType Container)
    Test-Check 'initialize returns canonical root' ($state.LogRoot -ceq [System.IO.Path]::GetFullPath($tempRoot))
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
    Test-Check 'retention keeps the boundary day' (Test-Path -LiteralPath $boundaryPath)
    Test-Check 'retention ignores files outside the logger prefix' (Test-Path -LiteralPath $foreignPath)

    $message = "Starting token=abc123 Bearer xyz`nsecond line"
    $properties = [ordered]@{
        Instance = 'DEMOES'
        Password = 'TopSecret'
        Note = 'authorization=BasicValue'
        Cookie = 'session-cookie-value'
    }
    $logPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.START' -Message $message -Properties $properties -TimestampUtc $reference
    $text = [IO.File]::ReadAllText($logPath)
    Test-Check 'write creates the expected daily log file' ([IO.Path]::GetFileName($logPath) -ceq 'TestLog-2026-10-06.log')
    Test-Check 'write keeps safe context' ($text -match 'Instance="DEMOES"')
    Test-Check 'write redacts sensitive property names' ($text -match 'Password="\[REDACTED\]"' -and $text -match 'Cookie="\[REDACTED\]"')
    Test-Check 'write redacts token and authorization assignments' ($text -match 'token=\[REDACTED\]' -and $text -match 'authorization=\[REDACTED\]')
    Test-Check 'write redacts bearer tokens' ($text -match 'Bearer \[REDACTED\]')
    Test-Check 'write does not contain supplied secret values' ($text -notmatch 'abc123|TopSecret|BasicValue|session-cookie-value|Bearer xyz')
    Test-Check 'write normalizes embedded newlines to one physical record' (([IO.File]::ReadAllLines($logPath)).Count -eq 1)

    $bytes = [IO.File]::ReadAllBytes($logPath)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Test-Check 'log is UTF-8 without BOM' (-not $hasUtf8Bom)

    $nextDay = $reference.AddDays(1)
    $nextPath = Write-SisqualRuntimeLog -Level WARN -EventCode 'RUNTIME.NEXTDAY' -Message 'next' -TimestampUtc $nextDay
    Test-Check 'daily rotation chooses a new file by UTC day' ([IO.Path]::GetFileName($nextPath) -ceq 'TestLog-2026-10-07.log')

    Test-Throws 'invalid event codes are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'bad event' -Message 'x' | Out-Null }
    Test-Throws 'unsafe property names are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.BADFIELD' -Message 'x' -Properties @{ 'bad field' = 'value' } | Out-Null }
}
finally {
    Remove-Module Sisqual.Runtime.Logging -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) {
    exit 1
}
