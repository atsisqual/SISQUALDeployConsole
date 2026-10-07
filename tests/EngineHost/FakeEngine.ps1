#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Fingerprint {
    param([string]$InstanceCode)
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes('fake-plan|' + [string]$InstanceCode)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function New-Result {
    param(
        [object]$Request,
        [bool]$Succeeded,
        [int]$FailedTargets = 0,
        [int]$ErrorCount = 0,
        [string]$ErrorMessage = '',
        [string]$Details = 'SAFE',
        [string]$ModeOverride = '',
        [switch]$InvalidArithmetic,
        [switch]$OmitSummary,
        [switch]$InvalidBackup
    )
    $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $mode = if ([string]::IsNullOrEmpty($ModeOverride)) { [string]$Request.mode } else { $ModeOverride }
    $result = [ordered]@{
        contractVersion = '0.1-proposed'
        operationId = [string]$Request.operationId
        engineCode = [string]$Request.engineCode
        engineVersion = 'test-1.0'
        mode = $mode
        startedAt = $now
        completedAt = $now
        succeeded = $Succeeded
        exitCode = if ($Succeeded) { 0 } else { 1 }
        errorMessage = $ErrorMessage
        summary = [ordered]@{ targetCount = 1; succeededTargets = if ($Succeeded) { 1 } else { 0 }; failedTargets = $FailedTargets; warningCount = 0; errorCount = $ErrorCount }
        results = @(
            [ordered]@{ timestamp = $now; instanceCode = [string]$Request.instanceCode; operationType = 'TEST_OBJECT'; object = 'ONE'; status = if ($Succeeded) { 'MATCHED' } else { 'ERROR' }; details = $Details },
            [ordered]@{ timestamp = $now; instanceCode = [string]$Request.instanceCode; operationType = 'TEST_OBJECT'; object = 'TWO'; status = 'INFO'; details = 'SECOND_ROW' }
        )
    }
    if ([string]$Request.mode -in @('PREVIEW','APPLY')) { $result.planFingerprint = Get-Fingerprint ([string]$Request.instanceCode) }
    if ($InvalidArithmetic) { $result.succeeded = $true; $result.summary.failedTargets = 1; $result.summary.errorCount = 1 }
    if ($OmitSummary) { [void]$result.Remove('summary') }
    if ($InvalidBackup) { $result.backup = [ordered]@{ created = 'yes'; unexpected = $true } }
    return $result
}

function Write-ResultFile {
    param([object]$Request, [object]$Result)
    [IO.File]::WriteAllText([string]$Request.resultPath, ($Result | ConvertTo-Json -Compress -Depth 30), [Text.UTF8Encoding]::new($false))
}

$raw = [Console]::In.ReadToEnd()
try {
    if ([string]::IsNullOrWhiteSpace($raw) -or [Text.UTF8Encoding]::new($false).GetByteCount($raw) -gt 1MB) { exit 2 }
    $request = $raw | ConvertFrom-Json -Depth 30
    foreach ($name in @('contractVersion','operationId','engineCode','mode','catalogPath','deadlineUtc','cancelPath','resultPath','secrets')) { if ($null -eq $request.PSObject.Properties[$name]) { exit 2 } }
    if ([string]$request.contractVersion -cne '0.1-proposed') { exit 2 }
    if ([string]$request.operationId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { exit 2 }
    if ([string]$request.engineCode -notmatch '^[A-Z][A-Z0-9_]{1,59}$' -or [string]$request.mode -notin @('PREVIEW','APPLY')) { exit 2 }
    if ([string]::IsNullOrWhiteSpace([string]$request.resultPath)) { exit 2 }
}
catch { exit 2 }

$scenario = [string]$request.instanceCode
if ([string]::IsNullOrWhiteSpace($scenario)) { $scenario = 'GOOD' }
$secretValue = ''
if ($null -ne $request.secrets) {
    $firstSecret = @($request.secrets.PSObject.Properties | Select-Object -First 1)
    if ($firstSecret.Count -eq 1) { $secretValue = [string]$firstSecret[0].Value }
}

if ($request.mode -eq 'APPLY') {
    $expected = Get-Fingerprint ([string]$request.instanceCode)
    if ([string]$request.planFingerprint -cne $expected) {
        Write-ResultFile $request (New-Result $request $false 1 1 'PLAN_CHANGED')
        exit 1
    }
}

switch ($scenario) {
    'SECRET_STDOUT' {
        [Console]::Out.WriteLine($secretValue)
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_STDERR' {
        [Console]::Error.WriteLine($secretValue)
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_RESULT' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $true -Details $secretValue)
        exit 0
    }
    'SECRET_BASE64' {
        [Console]::Out.WriteLine([Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($secretValue)))
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_URL' {
        [Console]::Error.WriteLine([Uri]::EscapeDataString($secretValue))
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'INVALID_ARITHMETIC' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $true -InvalidArithmetic)
        exit 0
    }
    'INVALID_MODE_ECHO' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $true -ModeOverride 'APPLY')
        exit 0
    }
    'INVALID_SHAPE' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $true -OmitSummary)
        exit 0
    }
    'INVALID_BACKUP' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $true -InvalidBackup)
        exit 0
    }
    'FAILED_PREVIEW' {
        Write-ResultFile $request (New-Result -Request $request -Succeeded $false -FailedTargets 1 -ErrorCount 1 -ErrorMessage 'EXPECTED_PREVIEW_FAILURE')
        exit 1
    }
    'UNEXPECTED_EXIT' {
        $result = New-Result $request $true
        $result.exitCode = 99
        Write-ResultFile $request $result
        exit 99
    }
    'NO_RESULT' { exit 0 }
    'STREAM_LIMIT' { [Console]::Out.Write(('X' * (1MB + 64KB))); exit 0 }
    'HANG_COOPERATIVE' {
        $limit = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath ([string]$request.cancelPath)) -and [DateTime]::UtcNow -lt $limit) { Start-Sleep -Milliseconds 50 }
        if (Test-Path -LiteralPath ([string]$request.cancelPath)) {
            Write-ResultFile $request (New-Result -Request $request -Succeeded $false -FailedTargets 1 -ErrorCount 1 -ErrorMessage 'CANCELLED')
            exit 1
        }
        exit 1
    }
    'HANG_IGNORE' {
        Start-Sleep -Seconds 15
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'ARGS_ENV_SAFE' {
        $leaked = $false
        if (-not [string]::IsNullOrEmpty($secretValue)) {
            if ([Environment]::CommandLine.Contains($secretValue, [StringComparison]::Ordinal)) { $leaked = $true }
            foreach ($entry in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
                if ([string]$entry.Value -and ([string]$entry.Value).Contains($secretValue, [StringComparison]::Ordinal)) { $leaked = $true; break }
            }
        }
        Write-ResultFile $request (New-Result -Request $request -Succeeded (-not $leaked) -FailedTargets $(if ($leaked) { 1 } else { 0 }) -ErrorCount $(if ($leaked) { 1 } else { 0 }) -ErrorMessage $(if ($leaked) { 'ARG_ENV_LEAK' } else { '' }) -Details $(if ($leaked) { 'ARGS_ENV_LEAK' } else { 'ARGS_ENV_SAFE' }))
        if ($leaked) { exit 1 } else { exit 0 }
    }
    default {
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
}
