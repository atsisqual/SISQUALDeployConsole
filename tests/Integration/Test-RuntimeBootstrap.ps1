[CmdletBinding()]
param([string]$OutputPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$library = Join-Path $repoRoot 'runtime\RuntimeBootstrap.ps1'
. $library

$checks = [Collections.Generic.List[object]]::new()
$fatal = $null
$tempRoot = Join-Path $env:TEMP ('SISQUAL-Phase3A-' + [guid]::NewGuid().ToString('N'))
$outsideRoot = $tempRoot + '-outside'
$junctionTarget = $tempRoot + '-junction-target'

function Add-Check([string]$Id, [bool]$Pass, [string]$Message) {
    [void]$checks.Add([pscustomobject][ordered]@{ Id = $Id; Status = $(if ($Pass) { 'PASS' } else { 'FAIL' }); Message = $Message })
}
function Throws([scriptblock]$Action) { try { & $Action; return $false } catch { return $true } }

try {
    New-Item -ItemType Directory -Path $tempRoot, $junctionTarget -Force | Out-Null
    $defaults = Get-SisqualRuntimeDefaults
    Add-Check 'DEFAULT_HOST_VERSION' ($defaults.ExpectedPowerShellVersion -ceq '7.6.6') 'Expected portable PowerShell version is pinned.'
    Add-Check 'DEFAULT_APPROVED_LOG_ROOT' ($defaults.ApprovedLogRoot -ceq 'C:\SISQUALWFM\WFM.Logs') 'Approved local log root is fixed.'
    Add-Check 'DEFAULT_LOG_ROOT' ($defaults.DefaultLogRoot -ceq 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement') 'Default log root matches ADR-0007.'
    Add-Check 'DEFAULT_RETENTION' ($defaults.RetentionDays -eq 30) 'Default retention is 30 days.'

    $hostResult = Test-SisqualRuntimeHost -ExpectedVersion '7.6.6'
    Add-Check 'HOST_ACCEPTS_PINNED_RUNTIME' $hostResult.Success 'The exact portable PowerShell host is accepted.'
    $wrongHostResult = Test-SisqualRuntimeHost -ExpectedVersion '0.0.0'
    Add-Check 'HOST_REJECTS_WRONG_VERSION' (-not $wrongHostResult.Success) 'A non-pinned PowerShell version is rejected.'

    $outsideRejected = Throws { Initialize-SisqualRuntimeLog -LogRoot $outsideRoot -ApprovedRoot $tempRoot -RetentionDays 30 | Out-Null }
    Add-Check 'LOG_ROOT_OUTSIDE_APPROVED_REJECTED' ($outsideRejected -and -not (Test-Path -LiteralPath $outsideRoot)) 'An outside log root is rejected before any filesystem side effect.'

    $junction = Join-Path $tempRoot 'junction'
    New-Item -ItemType Junction -Path $junction -Target $junctionTarget -Force | Out-Null
    $junctionChild = Join-Path $junction 'escaped-child'
    $junctionRejected = Throws { Initialize-SisqualRuntimeLog -LogRoot $junctionChild -ApprovedRoot $tempRoot -RetentionDays 30 | Out-Null }
    Add-Check 'LOG_ROOT_JUNCTION_REJECTED' ($junctionRejected -and -not (Test-Path -LiteralPath (Join-Path $junctionTarget 'escaped-child'))) 'A junction escape is rejected before creating the child.'
    Remove-Item -LiteralPath $junction -Force

    $logRoot = Join-Path $tempRoot 'logs'
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2000-01-01.log') -Value 'old' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $logRoot 'other-2000-01-01.log') -Value 'preserve' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2026-09-07.log') -Value 'keep-boundary' -Encoding ascii
    $now = [datetime]::SpecifyKind([datetime]'2026-10-06T12:00:00', [DateTimeKind]::Utc)
    $context = Initialize-SisqualRuntimeLog -LogRoot $logRoot -ApprovedRoot $tempRoot -RetentionDays 30 -NowUtc $now
    Add-Check 'LOG_DIRECTORY_READY' (Test-Path -LiteralPath $context.LogRoot -PathType Container) 'Log directory is created or reused.'
    Add-Check 'RETENTION_REMOVES_OLD_MATCHING_LOG' (-not (Test-Path -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2000-01-01.log'))) 'Expired matching log is removed.'
    Add-Check 'RETENTION_PRESERVES_UNRELATED_FILE' (Test-Path -LiteralPath (Join-Path $logRoot 'other-2000-01-01.log') -PathType Leaf) 'Unrelated files are not deleted.'
    Add-Check 'RETENTION_KEEPS_DAY_30' (Test-Path -LiteralPath (Join-Path $logRoot 'SISQUALDeployConsole-2026-09-07.log') -PathType Leaf) 'The 30th retained daily log is preserved.'
    Add-Check 'DAILY_LOG_NAME' ([IO.Path]::GetFileName($context.LogPath) -ceq 'SISQUALDeployConsole-2026-10-06.log') 'Daily log uses an invariant UTC date name.'
    Write-SisqualBootstrapEvent -LogPath $context.LogPath -EventId 'BOOTSTRAP_STARTED' -NowUtc $now
    Write-SisqualBootstrapEvent -LogPath $context.LogPath -EventId 'HOST_VALID' -NowUtc $now.AddSeconds(1)
    $lines = @(Get-Content -LiteralPath $context.LogPath)
    Add-Check 'LOG_APPEND' ($lines.Count -eq 2) 'Bootstrap events append to the same daily file.'
    Add-Check 'LOG_EVENT_CODES' (($lines[0] -match 'BOOTSTRAP_STARTED') -and ($lines[1] -match 'HOST_VALID')) 'Log lines carry fixed event codes.'
    $bytes = [IO.File]::ReadAllBytes($context.LogPath)
    Add-Check 'LOG_ASCII' (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0) 'Bootstrap log output is ASCII.'

    # Exercise the real launcher with a disposable sibling RuntimeBootstrap implementation that
    # succeeds during initialization but throws only for terminal event writes. This proves the
    # product script preserves exit 20/21 without adding a test hook to production code.
    $launcherPackage = Join-Path $tempRoot 'launcher-package'
    $launcherRuntime = Join-Path $launcherPackage 'runtime'
    New-Item -ItemType Directory -Path $launcherRuntime -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'runtime\Start-SisqualDeployConsole.ps1') -Destination (Join-Path $launcherRuntime 'Start-SisqualDeployConsole.ps1')
    $stub = @'
function Get-SisqualRuntimeDefaults { [pscustomobject]@{ ExpectedPowerShellVersion='7.6.6'; ApprovedLogRoot='C:\'; DefaultLogRoot='C:\'; ManifestFileName='package-manifest.json' } }
function Test-SisqualRuntimeHost { param($ExpectedVersion) [pscustomobject]@{ Success=$true; ExpectedVersion=$ExpectedVersion; ActualVersion='7.6.6'; PSEdition='Core'; Is64BitProcess=$true } }
function Initialize-SisqualRuntimeLog { param($LogRoot,$ApprovedRoot,$RetentionDays) [pscustomobject]@{ LogPath='discard.log' } }
function Write-SisqualBootstrapEvent { param($LogPath,$EventId,$Level='INFO') if ($EventId -in @('MANIFEST_MISSING','INTEGRITY_VERIFIER_UNAVAILABLE')) { throw ('forced terminal log failure: ' + $EventId) } }
'@
    Set-Content -LiteralPath (Join-Path $launcherRuntime 'RuntimeBootstrap.ps1') -Value $stub -Encoding ascii
    $launcher = Join-Path $launcherRuntime 'Start-SisqualDeployConsole.ps1'
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $childOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $launcher -LogRoot 'C:\' 2>&1
    $missingExit = $LASTEXITCODE
    Add-Check 'TERMINAL_LOG_FAILURE_PRESERVES_EXIT_20' ($missingExit -eq 20) 'Missing-manifest exit 20 survives terminal log append failure.'
    '{}' | Set-Content -LiteralPath (Join-Path $launcherPackage 'package-manifest.json') -Encoding ascii
    $childOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $launcher -LogRoot 'C:\' 2>&1
    $verifierExit = $LASTEXITCODE
    Add-Check 'TERMINAL_LOG_FAILURE_PRESERVES_EXIT_21' ($verifierExit -eq 21) 'Verifier-unavailable exit 21 survives terminal log append failure.'
}
catch {
    $fatal = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
}
finally {
    $passCount = @($checks | Where-Object Status -eq 'PASS').Count
    $failCount = @($checks | Where-Object Status -eq 'FAIL').Count
    $report = [pscustomobject][ordered]@{ Schema='SISQUAL_PHASE3A_RUNTIME_BOOTSTRAP_V1'; PowerShell=$PSVersionTable.PSVersion.ToString(); PassCount=$passCount; FailCount=$failCount; Fatal=$fatal; Checks=@($checks) }
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot 'phase3a-runtime-bootstrap-report.json' }
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $OutputPath -Encoding ascii
    foreach ($path in @($tempRoot, $outsideRoot, $junctionTarget)) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue } }
}

if ($null -ne $fatal -or @($checks | Where-Object Status -eq 'FAIL').Count -gt 0) { exit 1 }
exit 0
