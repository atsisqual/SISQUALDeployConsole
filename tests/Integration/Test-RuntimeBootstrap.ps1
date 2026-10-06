[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$library = Join-Path $repoRoot 'runtime\RuntimeBootstrap.ps1'
. $library

$checks = [System.Collections.Generic.List[object]]::new()
$fatal = $null
$tempRoot = Join-Path $env:TEMP ('SISQUAL-Phase3A-' + [guid]::NewGuid().ToString('N'))

function Add-Check {
    param(
        [string]$Id,
        [bool]$Pass,
        [string]$Message
    )

    [void]$checks.Add([pscustomobject][ordered]@{
        Id = $Id
        Status = $(if ($Pass) { 'PASS' } else { 'FAIL' })
        Message = $Message
    })
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $defaults = Get-SisqualRuntimeDefaults
    Add-Check 'DEFAULT_HOST_VERSION' ($defaults.ExpectedPowerShellVersion -ceq '7.6.6') 'Expected portable PowerShell version is pinned.'
    Add-Check 'DEFAULT_LOG_ROOT' ($defaults.DefaultLogRoot -ceq 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement') 'Default log root matches ADR-0007.'
    Add-Check 'DEFAULT_RETENTION' ($defaults.RetentionDays -eq 30) 'Default retention is 30 days.'

    $hostResult = Test-SisqualRuntimeHost -ExpectedVersion '7.6.6'
    Add-Check 'HOST_ACCEPTS_PINNED_RUNTIME' $hostResult.Success 'The exact portable PowerShell host is accepted.'

    $wrongHostResult = Test-SisqualRuntimeHost -ExpectedVersion '0.0.0'
    Add-Check 'HOST_REJECTS_WRONG_VERSION' (-not $wrongHostResult.Success) 'A non-pinned PowerShell version is rejected.'

    $logRoot = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2000-01-01.log') -Value 'old' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $logRoot 'other-2000-01-01.log') -Value 'preserve' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2026-09-07.log') -Value 'keep-boundary' -Encoding ascii

    $now = [datetime]::SpecifyKind([datetime]'2026-10-06T12:00:00', [DateTimeKind]::Utc)
    $context = Initialize-SisqualRuntimeLog -LogRoot $logRoot -RetentionDays 30 -NowUtc $now

    Add-Check 'LOG_DIRECTORY_READY' (Test-Path -LiteralPath $context.LogRoot -PathType Container) 'Log directory is created or reused.'
    Add-Check 'RETENTION_REMOVES_OLD_MATCHING_LOG' (-not (Test-Path -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2000-01-01.log'))) 'Expired matching log is removed.'
    Add-Check 'RETENTION_PRESERVES_UNRELATED_FILE' (Test-Path -LiteralPath (Join-Path $logRoot 'other-2000-01-01.log') -PathType Leaf) 'Unrelated files are not deleted.'
    Add-Check 'RETENTION_KEEPS_DAY_30' (Test-Path -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2026-09-07.log') -PathType Leaf) 'The 30th retained daily log is preserved.'

    $expectedDaily = Join-Path $logRoot 'SISQUALDeployConsole-2026-10-06.log'
    Add-Check 'DAILY_LOG_NAME' ($context.LogPath -ceq $expectedDaily) 'Daily log uses an invariant UTC date name.'

    Write-SisqualBootstrapEvent -LogPath $context.LogPath -EventId 'BOOTSTRAP_STARTED' -NowUtc $now
    Write-SisqualBootstrapEvent -LogPath $context.LogPath -EventId 'HOST_VALID' -NowUtc $now.AddSeconds(1)
    $lines = @(Get-Content -LiteralPath $context.LogPath)
    Add-Check 'LOG_APPEND' ($lines.Count -eq 2) 'Bootstrap events append to the same daily file.'
    Add-Check 'LOG_EVENT_CODES' (($lines[0] -match 'BOOTSTRAP_STARTED') -and ($lines[1] -match 'HOST_VALID')) 'Log lines carry fixed event codes.'

    $bytes = [IO.File]::ReadAllBytes($context.LogPath)
    $nonAscii = @($bytes | Where-Object { $_ -gt 127 })
    Add-Check 'LOG_ASCII' ($nonAscii.Count -eq 0) 'Bootstrap log output is ASCII.'
}
catch {
    $fatal = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
}
finally {
    $passCount = @($checks | Where-Object Status -eq 'PASS').Count
    $failCount = @($checks | Where-Object Status -eq 'FAIL').Count
    $report = [pscustomobject][ordered]@{
        Schema = 'SISQUAL_PHASE3A_RUNTIME_BOOTSTRAP_V1'
        PowerShell = $PSVersionTable.PSVersion.ToString()
        PassCount = $passCount
        FailCount = $failCount
        Fatal = $fatal
        Checks = @($checks)
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $PSScriptRoot 'phase3a-runtime-bootstrap-report.json'
    }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding ascii

    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($null -ne $fatal -or @($checks | Where-Object Status -eq 'FAIL').Count -gt 0) {
    exit 1
}
exit 0
