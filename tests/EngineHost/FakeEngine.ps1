#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Value {
    param([object]$Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-Fingerprint {
    param([string]$InstanceCode)
    $text = 'fake-plan|' + [string]$InstanceCode
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
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
        [switch]$OmitSummary
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
        summary = [ordered]@{
            targetCount = 1
            succeededTargets = if ($Succeeded) { 1 } else { 0 }
            failedTargets = $FailedTargets
            warningCount = 0
            errorCount = $ErrorCount
        }
        results = @(
            [ordered]@{
                timestamp = $now
                instanceCode = [string]$Request.instanceCode
                operationType = 'TEST_OBJECT'
                object = 'ONE'
                status = if ($Succeeded) { 'MATCHED' } else { 'ERROR' }
                details = $Details
            },
            [ordered]@{
                timestamp = $now
                instanceCode = [string]$Request.instanceCode
                operationType = 'TEST_OBJECT'
                object = 'TWO'
                status = 'INFO'
                details = 'SECOND_ROW'
            }
        )
    }
    if ([string]$Request.mode -eq 'PREVIEW' -or [string]$Request.mode -eq 'APPLY') {
        $result.planFingerprint = Get-Fingerprint -InstanceCode ([string]$Request.instanceCode)
    }
    if ($InvalidArithmetic) {
        $result.succeeded = $true
        $result.summary.failedTargets = 1
        $result.summary.errorCount = 1
    }
    if ($OmitSummary) { [void]$result.Remove('summary') }
    return $result
}

function Write-ResultFile {
    param([object]$Request, [object]$Result)
    $json = $Result | ConvertTo-Json -Compress -Depth 30
    [IO.File]::WriteAllText([string]$Request.resultPath, $json, [Text.UTF8Encoding]::new($false))
}

$raw = [Console]::In.ReadToEnd()
try {
    if ([string]::IsNullOrWhiteSpace($raw) -or [Text.UTF8Encoding]::new($false).GetByteCount($raw) -gt 1MB) { exit 2 }
    $request = $raw | ConvertFrom-Json -Depth 30
    foreach ($name in @('contractVersion','operationId','engineCode','mode','catalogPath','deadlineUtc','cancelPath','resultPath','secrets')) {
        if ($null -eq $request.PSObject.Properties[$name]) { exit 2 }
    }
    if ([string]$request.contractVersion -cne '0.1-proposed') { exit 2 }
    if ([string]$request.operationId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { exit 2 }
    if ([string]$request.engineCode -notmatch '^[A-Z][A-Z0-9_]{1,59}$') { exit 2 }
    if ([string]$request.mode -notin @('PREVIEW','APPLY')) { exit 2 }
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
    $expected = Get-Fingerprint -InstanceCode ([string]$request.instanceCode)
    if ([string]$request.planFingerprint -cne $expected) {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $false -FailedTargets 1 -ErrorCount 1 -ErrorMessage 'PLAN_CHANGED')
        exit 1
    }
}

switch ($scenario) {
    'SECRET_STDOUT' {
        [Console]::Out.WriteLine($secretValue)
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
        exit 0
    }
    'SECRET_STDERR' {
        [Console]::Error.WriteLine($secretValue)
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
        exit 0
    }
    'SECRET_RESULT' {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true -Details $secretValue)
        exit 0
    }
    'SECRET_BASE64' {
        $encoded = [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($secretValue))
        [Console]::Out.WriteLine($encoded)
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
        exit 0
    }
    'SECRET_URL' {
        [Console]::Error.WriteLine([Uri]::EscapeDataString($secretValue))
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
        exit 0
    }
    'INVALID_ARITHMETIC' {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true -InvalidArithmetic)
        exit 0
    }
    'INVALID_MODE_ECHO' {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true -ModeOverride 'APPLY')
        exit 0
    }
    'INVALID_SHAPE' {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true -OmitSummary)
        exit 0
    }
    'NO_RESULT' { exit 0 }
    'STREAM_LIMIT' {
        [Console]::Out.Write(('X' * (1MB + 64KB)))
        exit 0
    }
    'HANG_COOPERATIVE' {
        $limit = [DateTime]::UtcNow.AddSeconds(15)
        while (-not (Test-Path -LiteralPath ([string]$request.cancelPath)) -and [DateTime]::UtcNow -lt $limit) { Start-Sleep -Milliseconds 50 }
        if (Test-Path -LiteralPath ([string]$request.cancelPath)) {
            Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $false -FailedTargets 1 -ErrorCount 1 -ErrorMessage 'CANCELLED')
            exit 1
        }
        exit 1
    }
    'HANG_IGNORE' {
        Start-Sleep -Seconds 15
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
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
        $details = if ($leaked) { 'ARGS_ENV_LEAK' } else { 'ARGS_ENV_SAFE' }
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded (-not $leaked) -FailedTargets $(if ($leaked) { 1 } else { 0 }) -ErrorCount $(if ($leaked) { 1 } else { 0 }) -ErrorMessage $(if ($leaked) { 'ARG_ENV_LEAK' } else { '' }) -Details $details)
        if ($leaked) { exit 1 } else { exit 0 }
    }
    default {
        Write-ResultFile -Request $request -Result (New-Result -Request $request -Succeeded $true)
        exit 0
    }
}
