[CmdletBinding()]
param(
    [string]$ReportPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'OperationCoordinator.psm1'
Import-Module -Name $modulePath -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $PSScriptRoot 'operation-coordinator-report.json'
}

$tempRoot = Join-Path $env:TEMP ('SISQUALDeployConsole-Phase1C-Ops-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$checks = [System.Collections.Generic.List[object]]::new()
$rawIdempotencyKeys = [System.Collections.Generic.List[string]]::new()
$fatal = $null

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Message,
        $Data = $null
    )

    $checks.Add([pscustomobject][ordered]@{
        Id = $Id
        Status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Message = $Message
        Data = $Data
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function New-IdempotencyKey {
    $value = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $rawIdempotencyKeys.Add($value) | Out-Null
    return $value
}

function Wait-OperationTerminal {
    param(
        [Parameter(Mandatory = $true)]$Coordinator,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [int]$TimeoutMilliseconds = 5000
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $snapshot = Get-SisqualOperation -Coordinator $Coordinator -OperationId $OperationId
        if ($null -eq $snapshot) {
            return $null
        }
        if ($snapshot.Status -in @('SUCCEEDED', 'FAILED', 'CANCELLED')) {
            return $snapshot
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            return $snapshot
        }
        Start-Sleep -Milliseconds 25
    } while ($true)
}

function Get-MarkerLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }
    return @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Invoke-ConcurrentStatusReads {
    param(
        [Parameter(Mandatory = $true)]$Coordinator,
        [Parameter(Mandatory = $true)][string]$OperationId,
        [ValidateRange(2, 16)][int]$ReaderCount = 8
    )

    $barrier = [Threading.Barrier]::new($ReaderCount)
    $readers = [System.Collections.Generic.List[object]]::new()
    $statuses = [System.Collections.Generic.List[string]]::new()
    $errorCount = 0
    $scriptText = @'
param($ModulePath, $Coordinator, $OperationId, $Barrier)
Import-Module -Name $ModulePath -Force -ErrorAction Stop
if (-not $Barrier.SignalAndWait(10000)) { throw 'Concurrent reader barrier timed out.' }
Get-SisqualOperation -Coordinator $Coordinator -OperationId $OperationId
'@

    try {
        for ($i = 0; $i -lt $ReaderCount; $i++) {
            $ps = [PowerShell]::Create()
            $null = $ps.AddScript($scriptText)
            $null = $ps.AddArgument($modulePath)
            $null = $ps.AddArgument($Coordinator)
            $null = $ps.AddArgument($OperationId)
            $null = $ps.AddArgument($barrier)
            $async = $ps.BeginInvoke()
            $readers.Add([pscustomobject]@{ PowerShell = $ps; Async = $async }) | Out-Null
        }

        foreach ($reader in $readers) {
            try {
                $output = @($reader.PowerShell.EndInvoke($reader.Async))
                if ($reader.PowerShell.HadErrors) {
                    $errorCount++
                }
                foreach ($item in $output) {
                    if ($null -ne $item -and $null -ne $item.PSObject.Properties['Status']) {
                        $statuses.Add([string]$item.Status) | Out-Null
                    }
                }
            }
            catch {
                $errorCount++
            }
        }
    }
    finally {
        foreach ($reader in $readers) {
            try { $reader.PowerShell.Dispose() } catch {}
        }
        $barrier.Dispose()
    }

    return [pscustomobject]@{
        ReaderCount = $ReaderCount
        ErrorCount = $errorCount
        Statuses = @($statuses)
    }
}

$worker = {
    param($OperationId, $CancellationToken, $Argument)

    $durationMs = [int]$Argument.DurationMs
    $stepMs = 25
    $elapsed = 0
    while ($elapsed -lt $durationMs) {
        if ([bool]$Argument.CheckCancellation -and $CancellationToken.IsCancellationRequested) {
            return [pscustomobject]@{ Outcome = 'CANCELLED' }
        }
        Start-Sleep -Milliseconds $stepMs
        $elapsed += $stepMs
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Argument.MarkerPath)) {
        [IO.File]::AppendAllText([string]$Argument.MarkerPath, "$OperationId`n", [Text.Encoding]::ASCII)
    }
    return [pscustomobject]@{ Outcome = 'SUCCEEDED' }
}

$coordinators = [System.Collections.Generic.List[object]]::new()

try {
    $planA = Get-Sha256Hex 'plan-A'
    $planB = Get-Sha256Hex 'plan-B'
    $planC = Get-Sha256Hex 'plan-C'
    Add-Check 'PLAN_FINGERPRINT_CONTRACT_CASE' ($planA -cmatch '^[0-9a-f]{64}$') 'Test plan fingerprint uses the lowercase SHA-256 representation required by the versioned contract.'

    $coordinator = New-SisqualOperationCoordinator -MaxConcurrentOperations 4
    $coordinators.Add($coordinator) | Out-Null
    Add-Check 'COORDINATOR_CREATED' ($null -ne $coordinator -and $coordinator.AcceptingOperations) 'Coordinator starts in accepting state.'

    $markerA = Join-Path $tempRoot 'marker-a.txt'
    $keyA = New-IdempotencyKey
    $first = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planA -IdempotencyKey $keyA -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 500; MarkerPath = $markerA; CheckCancellation = $true })
    Add-Check 'FIRST_OPERATION_ACCEPTED' ($first.Accepted -and -not $first.Reused -and $first.Reason -eq 'STARTED') 'First operation is accepted and receives an OperationId.' @{ Reason = $first.Reason }

    $duplicate = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planA -IdempotencyKey $keyA -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 500; MarkerPath = $markerA; CheckCancellation = $true })
    Add-Check 'DUPLICATE_REUSED_WHILE_RUNNING' ($duplicate.Accepted -and $duplicate.Reused -and $duplicate.OperationId -eq $first.OperationId) 'Same idempotency key plus same request reuses the in-flight OperationId.'

    $conflict = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planB -IdempotencyKey $keyA -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 100; MarkerPath = ''; CheckCancellation = $true })
    Add-Check 'IDEMPOTENCY_CONFLICT' (-not $conflict.Accepted -and $conflict.Reason -eq 'IDEMPOTENCY_CONFLICT') 'Reusing an idempotency key with a different plan fingerprint is rejected.' @{ Reason = $conflict.Reason }

    $modeConflict = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode PREVIEW -InstanceCode 'A' -IdempotencyKey $keyA -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 100; MarkerPath = ''; CheckCancellation = $true })
    Add-Check 'IDEMPOTENCY_MODE_CONFLICT' (-not $modeConflict.Accepted -and $modeConflict.Reason -eq 'IDEMPOTENCY_CONFLICT') 'Reusing an idempotency key for PREVIEW after APPLY is rejected because mode is part of the request fingerprint.' @{ Reason = $modeConflict.Reason }

    $lockConflict = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planB -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 100; MarkerPath = ''; CheckCancellation = $true })
    Add-Check 'INSTANCE_LOCK_BLOCKS_CONFLICT' (-not $lockConflict.Accepted -and $lockConflict.Reason -eq 'LOCK_CONFLICT' -and $lockConflict.BlockingOperationId -eq $first.OperationId) 'Second destructive operation on the same instance is blocked by the instance lock.' @{ Reason = $lockConflict.Reason }

    $markerB = Join-Path $tempRoot 'marker-b.txt'
    $parallel = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'B' -PlanFingerprint $planB -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 350; MarkerPath = $markerB; CheckCancellation = $true })
    Add-Check 'DIFFERENT_INSTANCE_PARALLEL' ($parallel.Accepted -and -not $parallel.Reused) 'Different instance can run concurrently when no shared lock conflicts.'

    $firstDone = Wait-OperationTerminal -Coordinator $coordinator -OperationId $first.OperationId
    $parallelDone = Wait-OperationTerminal -Coordinator $coordinator -OperationId $parallel.OperationId
    Add-Check 'PARALLEL_OPERATIONS_COMPLETE' ($firstDone.Status -eq 'SUCCEEDED' -and $parallelDone.Status -eq 'SUCCEEDED') 'Concurrent non-conflicting operations both complete successfully.' @{ First = $firstDone.Status; Second = $parallelDone.Status }

    $markerALines = @(Get-MarkerLines $markerA)
    Add-Check 'DUPLICATE_EXECUTES_ONCE' ($markerALines.Count -eq 1 -and $markerALines[0] -eq $first.OperationId) 'Duplicate request did not execute the worker twice.' @{ MarkerCount = $markerALines.Count }

    $afterCompleteReplay = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planA -IdempotencyKey $keyA -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 50; MarkerPath = $markerA; CheckCancellation = $true })
    Start-Sleep -Milliseconds 100
    $markerALines2 = @(Get-MarkerLines $markerA)
    Add-Check 'REPLAY_AFTER_COMPLETE_REUSES_RESULT' ($afterCompleteReplay.Accepted -and $afterCompleteReplay.Reused -and $afterCompleteReplay.OperationId -eq $first.OperationId -and $markerALines2.Count -eq 1) 'Idempotent replay after completion returns the original operation and does not mutate again.' @{ MarkerCount = $markerALines2.Count }

    $postLockMarker = Join-Path $tempRoot 'marker-post-lock.txt'
    $postLock = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planC -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 75; MarkerPath = $postLockMarker; CheckCancellation = $true })
    $postLockDone = Wait-OperationTerminal -Coordinator $coordinator -OperationId $postLock.OperationId
    Add-Check 'INSTANCE_LOCK_RELEASED' ($postLock.Accepted -and $postLockDone.Status -eq 'SUCCEEDED') 'Instance lock is released after terminal completion.' @{ Status = $postLockDone.Status }

    $previewOp = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode PREVIEW -InstanceCode 'PREVIEW' -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 50; MarkerPath = ''; CheckCancellation = $true })
    $previewDone = Wait-OperationTerminal -Coordinator $coordinator -OperationId $previewOp.OperationId
    Add-Check 'PREVIEW_WITHOUT_CONFIRMED_PLAN' ($previewOp.Accepted -and $previewDone.Status -eq 'SUCCEEDED' -and $previewDone.Mode -eq 'PREVIEW' -and [string]::IsNullOrEmpty($previewDone.PlanFingerprint)) 'PREVIEW can execute without a confirmed APPLY plan fingerprint and preserves its mode.' @{ Status = $previewDone.Status; Mode = $previewDone.Mode }

    $shared1 = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'A' -PlanFingerprint $planA -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -LockKeys @('SERVER:SHARED_TEST') -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 400; MarkerPath = ''; CheckCancellation = $true })
    $shared2 = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'B' -PlanFingerprint $planB -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -LockKeys @('SERVER:SHARED_TEST') -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 50; MarkerPath = ''; CheckCancellation = $true })
    Add-Check 'SHARED_LOCK_BLOCKS_OTHER_INSTANCE' ($shared1.Accepted -and -not $shared2.Accepted -and $shared2.Reason -eq 'LOCK_CONFLICT' -and $shared2.BlockingOperationId -eq $shared1.OperationId) 'Shared-resource lock blocks a conflicting operation on another instance.' @{ Reason = $shared2.Reason }
    $null = Wait-OperationTerminal -Coordinator $coordinator -OperationId $shared1.OperationId

    $shared3 = Start-SisqualOperation -Coordinator $coordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'B' -PlanFingerprint $planC -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -LockKeys @('SERVER:SHARED_TEST') -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 50; MarkerPath = ''; CheckCancellation = $true })
    $shared3Done = Wait-OperationTerminal -Coordinator $coordinator -OperationId $shared3.OperationId
    Add-Check 'SHARED_LOCK_RELEASED' ($shared3.Accepted -and $shared3Done.Status -eq 'SUCCEEDED') 'Shared-resource lock is released after terminal completion.'

    $raceCoordinator = New-SisqualOperationCoordinator
    $coordinators.Add($raceCoordinator) | Out-Null
    $raceOp = Start-SisqualOperation -Coordinator $raceCoordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'RACE' -PlanFingerprint $planA -IdempotencyKey (New-IdempotencyKey) -CancellationMode NONE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 150; MarkerPath = ''; CheckCancellation = $false })
    Start-Sleep -Milliseconds 350
    $raceRead = Invoke-ConcurrentStatusReads -Coordinator $raceCoordinator -OperationId $raceOp.OperationId -ReaderCount 8
    $raceFinal = Wait-OperationTerminal -Coordinator $raceCoordinator -OperationId $raceOp.OperationId -TimeoutMilliseconds 2000
    Add-Check 'CONCURRENT_FINALIZATION_NO_ERROR' ($raceRead.ErrorCount -eq 0) 'Synchronized concurrent status readers do not race EndInvoke/disposal.' @{ Readers = $raceRead.ReaderCount; Errors = $raceRead.ErrorCount; ObservedStatuses = @($raceRead.Statuses) }
    Add-Check 'CONCURRENT_FINALIZATION_TERMINAL' ($raceFinal.Status -eq 'SUCCEEDED') 'Operation reaches a stable terminal state after concurrent finalization attempts.' @{ Status = $raceFinal.Status }
    Close-SisqualOperationCoordinator -Coordinator $raceCoordinator

    $cancelCoordinator = New-SisqualOperationCoordinator
    $coordinators.Add($cancelCoordinator) | Out-Null
    $cancelMarker = Join-Path $tempRoot 'cancel-marker.txt'
    $cancelOp = Start-SisqualOperation -Coordinator $cancelCoordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'C' -PlanFingerprint $planA -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 3000; MarkerPath = $cancelMarker; CheckCancellation = $true })
    Start-Sleep -Milliseconds 100
    $cancelRequest = Request-SisqualOperationCancellation -Coordinator $cancelCoordinator -OperationId $cancelOp.OperationId
    $cancelDone = Wait-OperationTerminal -Coordinator $cancelCoordinator -OperationId $cancelOp.OperationId -TimeoutMilliseconds 3000
    Add-Check 'EXPLICIT_CANCEL_ACCEPTED' ($cancelRequest.Accepted -and $cancelRequest.Reason -eq 'CANCELLATION_REQUESTED') 'Explicit cooperative cancellation request is accepted.'
    Add-Check 'COOPERATIVE_CANCEL_TERMINATES' ($cancelDone.Status -eq 'CANCELLED' -and $cancelDone.CancellationRequested) 'Cooperative worker reaches CANCELLED terminal state.' @{ Status = $cancelDone.Status }
    Add-Check 'CANCEL_BEFORE_MUTATION' (@(Get-MarkerLines $cancelMarker).Count -eq 0) 'Cancelled worker did not reach its simulated mutation marker.'
    Close-SisqualOperationCoordinator -Coordinator $cancelCoordinator

    $shutdownCoordinator = New-SisqualOperationCoordinator
    $coordinators.Add($shutdownCoordinator) | Out-Null
    $shutdownMarker = Join-Path $tempRoot 'shutdown-cancel-marker.txt'
    $shutdownOp = Start-SisqualOperation -Coordinator $shutdownCoordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'D' -PlanFingerprint $planA -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 3000; MarkerPath = $shutdownMarker; CheckCancellation = $true })
    Start-Sleep -Milliseconds 100
    $shutdown = Request-SisqualCoordinatorShutdown -Coordinator $shutdownCoordinator -WaitMilliseconds 3000 -CancelCooperativeOperations
    $shutdownDone = Get-SisqualOperation -Coordinator $shutdownCoordinator -OperationId $shutdownOp.OperationId
    Add-Check 'SHUTDOWN_CANCELS_COOPERATIVE' ($shutdown.ReadyToExit -and $shutdownDone.Status -eq 'CANCELLED') 'Controlled shutdown cancels cooperative active operation and drains before exit.' @{ Status = $shutdownDone.Status }
    Add-Check 'SHUTDOWN_CANCEL_NO_MUTATION' (@(Get-MarkerLines $shutdownMarker).Count -eq 0) 'Shutdown-cancelled operation did not reach simulated mutation marker.'
    $rejectedAfterShutdown = Start-SisqualOperation -Coordinator $shutdownCoordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'E' -PlanFingerprint $planB -IdempotencyKey (New-IdempotencyKey) -CancellationMode COOPERATIVE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 50; MarkerPath = ''; CheckCancellation = $true })
    Add-Check 'SHUTDOWN_STOPS_ADMISSION' (-not $rejectedAfterShutdown.Accepted -and $rejectedAfterShutdown.Reason -eq 'SHUTTING_DOWN') 'Once shutdown begins, new operations are rejected.' @{ Reason = $rejectedAfterShutdown.Reason }
    Close-SisqualOperationCoordinator -Coordinator $shutdownCoordinator

    $blockingCoordinator = New-SisqualOperationCoordinator
    $coordinators.Add($blockingCoordinator) | Out-Null
    $blockingMarker = Join-Path $tempRoot 'blocking-marker.txt'
    $blockingOp = Start-SisqualOperation -Coordinator $blockingCoordinator -EngineCode 'TEST_ENGINE' -Mode APPLY -InstanceCode 'F' -PlanFingerprint $planA -IdempotencyKey (New-IdempotencyKey) -CancellationMode NONE -WorkerScript $worker -WorkerArgument ([pscustomobject]@{ DurationMs = 1200; MarkerPath = $blockingMarker; CheckCancellation = $false })
    Start-Sleep -Milliseconds 100
    $nonCancel = Request-SisqualOperationCancellation -Coordinator $blockingCoordinator -OperationId $blockingOp.OperationId
    Add-Check 'NONCANCELLABLE_CANCEL_REJECTED' (-not $nonCancel.Accepted -and $nonCancel.Reason -eq 'NOT_CANCELLABLE') 'Operation declared non-cancellable rejects cancellation request.' @{ Reason = $nonCancel.Reason }

    $blockedShutdown = Request-SisqualCoordinatorShutdown -Coordinator $blockingCoordinator -WaitMilliseconds 100 -CancelCooperativeOperations
    Add-Check 'SHUTDOWN_BLOCKED_BY_ACTIVE_OPERATION' (-not $blockedShutdown.ReadyToExit -and $blockedShutdown.ActiveOperationIds -contains $blockingOp.OperationId) 'Shutdown reports blocked instead of force-stopping a non-cancellable active operation.' @{ ActiveCount = @($blockedShutdown.ActiveOperationIds).Count }

    $closeBlocked = $false
    try {
        Close-SisqualOperationCoordinator -Coordinator $blockingCoordinator
    }
    catch {
        $closeBlocked = $true
    }
    Add-Check 'FORCE_CLOSE_NOT_ALLOWED' $closeBlocked 'Coordinator refuses to close while an operation remains active.'

    $blockingDone = Wait-OperationTerminal -Coordinator $blockingCoordinator -OperationId $blockingOp.OperationId -TimeoutMilliseconds 3000
    $drainedShutdown = Request-SisqualCoordinatorShutdown -Coordinator $blockingCoordinator -WaitMilliseconds 500
    Add-Check 'SHUTDOWN_READY_AFTER_DRAIN' ($blockingDone.Status -eq 'SUCCEEDED' -and $drainedShutdown.ReadyToExit) 'Shutdown becomes ready only after the non-cancellable operation reaches a terminal state.' @{ Status = $blockingDone.Status }
    Add-Check 'NONCANCELLABLE_OPERATION_NOT_KILLED' (@(Get-MarkerLines $blockingMarker).Count -eq 1) 'Non-cancellable worker completed its simulated mutation instead of being force-killed.'
    Close-SisqualOperationCoordinator -Coordinator $blockingCoordinator

    $snapshot = Get-SisqualOperation -Coordinator $coordinator -OperationId $first.OperationId
    Add-Check 'PLAN_FINGERPRINT_PRESERVED' ($snapshot.PlanFingerprint -ceq $planA) 'Operation snapshot preserves the exact lowercase validated plan fingerprint.' @{ PlanFingerprint = $snapshot.PlanFingerprint }
    Add-Check 'IDEMPOTENCY_KEY_NOT_EXPOSED' ($null -eq $snapshot.PSObject.Properties['IdempotencyKey'] -and -not [string]::IsNullOrWhiteSpace($snapshot.IdempotencyKeyHash)) 'Snapshot exposes only the idempotency-key hash, not the raw token.'

    $stableFinal = $true
    for ($i = 0; $i -lt 20; $i++) {
        $repeatSnapshot = Get-SisqualOperation -Coordinator $coordinator -OperationId $first.OperationId
        if ($repeatSnapshot.Status -ne 'SUCCEEDED') {
            $stableFinal = $false
            break
        }
    }
    Add-Check 'TERMINAL_FINALIZATION_STABLE' $stableFinal 'Repeated terminal reads remain stable after pipeline finalization.'

    $shutdownMain = Request-SisqualCoordinatorShutdown -Coordinator $coordinator -WaitMilliseconds 1000
    Add-Check 'DRAINED_COORDINATOR_READY' $shutdownMain.ReadyToExit 'Coordinator with no active work is immediately ready to exit.'
    Close-SisqualOperationCoordinator -Coordinator $coordinator
    Add-Check 'CLOSE_AFTER_DRAIN' $coordinator.Closed 'Coordinator closes cleanly after all operations are terminal.'
}
catch {
    $fatal = $_.Exception.ToString()
}
finally {
    foreach ($coordinator in $coordinators) {
        try {
            if (-not $coordinator.Closed) {
                $null = Request-SisqualCoordinatorShutdown -Coordinator $coordinator -WaitMilliseconds 3000 -CancelCooperativeOperations
                try { Close-SisqualOperationCoordinator -Coordinator $coordinator } catch {}
            }
        }
        catch {}
    }
}

$preReport = [pscustomobject][ordered]@{
    Schema = 'SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1'
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Platform = [Environment]::OSVersion.VersionString
    PassCount = @($checks | Where-Object Status -eq 'PASS').Count
    FailCount = @($checks | Where-Object Status -eq 'FAIL').Count
    Fatal = $fatal
    Checks = @($checks)
}

$json = $preReport | ConvertTo-Json -Depth 10
$rawTokenLeak = $false
foreach ($key in $rawIdempotencyKeys) {
    if ($json.Contains($key, [StringComparison]::Ordinal)) {
        $rawTokenLeak = $true
        break
    }
}
Add-Check 'NO_RAW_IDEMPOTENCY_TOKEN_IN_REPORT' (-not $rawTokenLeak) 'Report does not contain any raw idempotency token.' @{ TokenCountChecked = $rawIdempotencyKeys.Count }

$report = [pscustomobject][ordered]@{
    Schema = 'SISQUAL_PHASE1C_OPERATION_COORDINATOR_V1'
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    Platform = [Environment]::OSVersion.VersionString
    PassCount = @($checks | Where-Object Status -eq 'PASS').Count
    FailCount = @($checks | Where-Object Status -eq 'FAIL').Count
    Fatal = $fatal
    Checks = @($checks)
}

$json = $report | ConvertTo-Json -Depth 10
$parent = Split-Path -Parent $ReportPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}
[IO.File]::WriteAllText($ReportPath, $json + "`n", [Text.UTF8Encoding]::new($false))

try { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue } catch {}

Write-Host ("Phase 1C operation coordinator: {0} PASS / {1} FAIL" -f $report.PassCount, $report.FailCount)
if ($fatal -or $report.FailCount -gt 0) {
    if ($fatal) { Write-Error $fatal }
    exit 1
}
exit 0
