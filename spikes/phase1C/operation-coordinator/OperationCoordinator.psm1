Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-CanonicalLockKeys {
    param(
        [string]$InstanceCode,
        [string[]]$LockKeys
    )

    $keys = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($InstanceCode)) {
        $keys.Add("INSTANCE:$InstanceCode")
    }

    foreach ($key in @($LockKeys)) {
        if ([string]::IsNullOrWhiteSpace($key)) {
            continue
        }
        $keys.Add([string]$key)
    }

    $distinct = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $keys) {
        $null = $distinct.Add($key)
    }

    $result = @($distinct)
    [Array]::Sort($result, [StringComparer]::Ordinal)
    return $result
}

function Get-RequestFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$EngineCode,
        [string]$InstanceCode,
        [Parameter(Mandatory = $true)][string]$PlanFingerprint,
        [Parameter(Mandatory = $true)][ValidateSet('COOPERATIVE', 'NONE')][string]$CancellationMode,
        [string[]]$LockKeys
    )

    $parts = @(
        $EngineCode,
        ([string]$InstanceCode),
        $PlanFingerprint,
        $CancellationMode
    ) + @($LockKeys)

    return ConvertTo-Sha256Hex -Value ($parts -join "`n")
}

function New-OrdinalDictionary {
    return [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
}

function Invoke-WithCoordinatorLock {
    param(
        [Parameter(Mandatory = $true)]$Coordinator,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    [Threading.Monitor]::Enter($Coordinator.SyncRoot)
    try {
        return & $ScriptBlock
    }
    finally {
        [Threading.Monitor]::Exit($Coordinator.SyncRoot)
    }
}

function Test-TerminalStatus {
    param([string]$Status)
    return $Status -in @('SUCCEEDED', 'FAILED', 'CANCELLED')
}

function New-SisqualOperationCoordinator {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 16)]
        [int]$MaxConcurrentOperations = 4
    )

    $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxConcurrentOperations)
    $pool.Open()

    return [pscustomobject][ordered]@{
        PSTypeName = 'SISQUAL.OperationCoordinator'
        SyncRoot = [object]::new()
        RunspacePool = $pool
        AcceptingOperations = $true
        ShutdownRequested = $false
        Closed = $false
        Operations = (New-OrdinalDictionary)
        Idempotency = (New-OrdinalDictionary)
        Locks = (New-OrdinalDictionary)
    }
}

function Update-SisqualOperationCoordinator {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Coordinator)

    $completed = [System.Collections.Generic.List[object]]::new()

    $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        foreach ($operation in @($Coordinator.Operations.Values)) {
            if ((Test-TerminalStatus -Status $operation.Status) -or $null -eq $operation.AsyncResult) {
                continue
            }

            if ($operation.AsyncResult.IsCompleted) {
                $completed.Add($operation) | Out-Null
            }
        }
    }

    foreach ($operation in $completed) {
        $outcome = 'SUCCEEDED'
        $errorText = $null
        try {
            $output = @($operation.PowerShell.EndInvoke($operation.AsyncResult))
            $last = $output | Select-Object -Last 1
            if ($null -ne $last -and $null -ne $last.PSObject.Properties['Outcome']) {
                $outcome = [string]$last.Outcome
            }
            if ($operation.PowerShell.HadErrors) {
                $outcome = 'FAILED'
                $errorText = 'Worker pipeline reported an error.'
            }
        }
        catch {
            $outcome = 'FAILED'
            $errorText = $_.Exception.GetType().FullName
        }

        $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            if (-not (Test-TerminalStatus -Status $operation.Status)) {
                if ($outcome -eq 'CANCELLED') {
                    $operation.Status = 'CANCELLED'
                }
                elseif ($outcome -eq 'SUCCEEDED') {
                    $operation.Status = 'SUCCEEDED'
                }
                else {
                    $operation.Status = 'FAILED'
                }
                $operation.FinishedAt = [DateTime]::UtcNow
                $operation.ErrorType = $errorText
            }

            foreach ($lockKey in $operation.LockKeys) {
                if ($Coordinator.Locks.ContainsKey($lockKey) -and [string]$Coordinator.Locks[$lockKey] -eq $operation.OperationId) {
                    $null = $Coordinator.Locks.Remove($lockKey)
                }
            }
        }

        $operation.PowerShell.Dispose()
        $operation.PowerShell = $null
        $operation.AsyncResult = $null
        $operation.CancellationSource.Dispose()
        $operation.CancellationSource = $null
    }
}

function Start-SisqualOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Z0-9_]+$')][string]$EngineCode,
        [string]$InstanceCode,
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$PlanFingerprint,
        [Parameter(Mandatory = $true)][ValidateLength(16, 256)][string]$IdempotencyKey,
        [ValidateSet('COOPERATIVE', 'NONE')][string]$CancellationMode = 'COOPERATIVE',
        [string[]]$LockKeys = @(),
        [Parameter(Mandatory = $true)][scriptblock]$WorkerScript,
        $WorkerArgument,
        [Parameter(Mandatory = $true)]$Coordinator
    )

    Update-SisqualOperationCoordinator -Coordinator $Coordinator
    $canonicalLocks = @(Get-CanonicalLockKeys -InstanceCode $InstanceCode -LockKeys $LockKeys)
    if ($canonicalLocks.Count -eq 0) {
        throw 'At least one instance or explicit lock key is required.'
    }

    $requestFingerprint = Get-RequestFingerprint -EngineCode $EngineCode -InstanceCode $InstanceCode -PlanFingerprint $PlanFingerprint.ToUpperInvariant() -CancellationMode $CancellationMode -LockKeys $canonicalLocks
    $idempotencyHash = ConvertTo-Sha256Hex -Value $IdempotencyKey

    $decision = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if ($Coordinator.Closed) {
            return [pscustomobject]@{
                Result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'COORDINATOR_CLOSED'; OperationId = $null; BlockingOperationId = $null }
                Operation = $null
            }
        }

        if ($Coordinator.Idempotency.ContainsKey($IdempotencyKey)) {
            $existing = $Coordinator.Idempotency[$IdempotencyKey]
            if ([string]$existing.RequestFingerprint -eq $requestFingerprint) {
                $replayResult = [pscustomobject]@{ Accepted = $true; Reused = $true; Reason = 'IDEMPOTENT_REPLAY'; OperationId = [string]$existing.OperationId; BlockingOperationId = $null }
            }
            else {
                $replayResult = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'IDEMPOTENCY_CONFLICT'; OperationId = [string]$existing.OperationId; BlockingOperationId = $null }
            }
            return [pscustomobject]@{ Result = $replayResult; Operation = $null }
        }

        if (-not $Coordinator.AcceptingOperations) {
            return [pscustomobject]@{
                Result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'SHUTTING_DOWN'; OperationId = $null; BlockingOperationId = $null }
                Operation = $null
            }
        }

        foreach ($lockKey in $canonicalLocks) {
            if ($Coordinator.Locks.ContainsKey($lockKey)) {
                return [pscustomobject]@{
                    Result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'LOCK_CONFLICT'; OperationId = $null; BlockingOperationId = [string]$Coordinator.Locks[$lockKey]; LockKey = $lockKey }
                    Operation = $null
                }
            }
        }

        $operationId = [guid]::NewGuid().ToString('D')
        $cancellationSource = [Threading.CancellationTokenSource]::new()
        $newOperation = [pscustomobject][ordered]@{
            OperationId = $operationId
            EngineCode = $EngineCode
            InstanceCode = [string]$InstanceCode
            PlanFingerprint = $PlanFingerprint.ToUpperInvariant()
            RequestFingerprint = $requestFingerprint
            IdempotencyKeyHash = $idempotencyHash
            CancellationMode = $CancellationMode
            CancellationRequested = $false
            LockKeys = $canonicalLocks
            Status = 'QUEUED'
            StartedAt = $null
            FinishedAt = $null
            ErrorType = $null
            CancellationSource = $cancellationSource
            PowerShell = $null
            AsyncResult = $null
        }

        $Coordinator.Operations.Add($operationId, $newOperation)
        $Coordinator.Idempotency.Add($IdempotencyKey, [pscustomobject]@{ OperationId = $operationId; RequestFingerprint = $requestFingerprint })
        foreach ($lockKey in $canonicalLocks) {
            $Coordinator.Locks.Add($lockKey, $operationId)
        }

        return [pscustomobject]@{ Result = $null; Operation = $newOperation }
    }

    if ($null -ne $decision.Result) {
        return $decision.Result
    }
    $operation = $decision.Operation

    $powerShell = [PowerShell]::Create()
    $powerShell.RunspacePool = $Coordinator.RunspacePool
    $null = $powerShell.AddScript($WorkerScript.ToString())
    $null = $powerShell.AddArgument($operation.OperationId)
    $null = $powerShell.AddArgument($operation.CancellationSource.Token)
    $null = $powerShell.AddArgument($WorkerArgument)

    try {
        $asyncResult = $powerShell.BeginInvoke()
        $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $operation.PowerShell = $powerShell
            $operation.AsyncResult = $asyncResult
            $operation.Status = 'RUNNING'
            $operation.StartedAt = [DateTime]::UtcNow
        }
    }
    catch {
        $caughtType = $_.Exception.GetType().FullName
        $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $operation.Status = 'FAILED'
            $operation.FinishedAt = [DateTime]::UtcNow
            $operation.ErrorType = $caughtType
            foreach ($lockKey in $operation.LockKeys) {
                if ($Coordinator.Locks.ContainsKey($lockKey) -and [string]$Coordinator.Locks[$lockKey] -eq $operation.OperationId) {
                    $null = $Coordinator.Locks.Remove($lockKey)
                }
            }
        }
        $powerShell.Dispose()
        $operation.CancellationSource.Dispose()
        throw
    }

    return [pscustomobject]@{ Accepted = $true; Reused = $false; Reason = 'STARTED'; OperationId = $operation.OperationId; BlockingOperationId = $null }
}

function Get-SisqualOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)]$Coordinator
    )

    Update-SisqualOperationCoordinator -Coordinator $Coordinator
    return Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if (-not $Coordinator.Operations.ContainsKey($OperationId)) {
            return $null
        }
        $operation = $Coordinator.Operations[$OperationId]
        return [pscustomobject][ordered]@{
            OperationId = $operation.OperationId
            EngineCode = $operation.EngineCode
            InstanceCode = $operation.InstanceCode
            PlanFingerprint = $operation.PlanFingerprint
            RequestFingerprint = $operation.RequestFingerprint
            IdempotencyKeyHash = $operation.IdempotencyKeyHash
            CancellationMode = $operation.CancellationMode
            CancellationRequested = [bool]$operation.CancellationRequested
            LockKeys = @($operation.LockKeys)
            Status = $operation.Status
            StartedAt = $operation.StartedAt
            FinishedAt = $operation.FinishedAt
            ErrorType = $operation.ErrorType
        }
    }
}

function Request-SisqualOperationCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)]$Coordinator
    )

    Update-SisqualOperationCoordinator -Coordinator $Coordinator
    return Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if (-not $Coordinator.Operations.ContainsKey($OperationId)) {
            return [pscustomobject]@{ Accepted = $false; Reason = 'NOT_FOUND'; OperationId = $OperationId }
        }

        $operation = $Coordinator.Operations[$OperationId]
        if (Test-TerminalStatus -Status $operation.Status) {
            return [pscustomobject]@{ Accepted = $true; Reason = 'ALREADY_FINISHED'; OperationId = $OperationId }
        }

        if ($operation.CancellationMode -ne 'COOPERATIVE') {
            return [pscustomobject]@{ Accepted = $false; Reason = 'NOT_CANCELLABLE'; OperationId = $OperationId }
        }

        if (-not $operation.CancellationRequested) {
            $operation.CancellationRequested = $true
            $operation.Status = 'CANCELLING'
            $operation.CancellationSource.Cancel()
        }
        return [pscustomobject]@{ Accepted = $true; Reason = 'CANCELLATION_REQUESTED'; OperationId = $OperationId }
    }
}

function Request-SisqualCoordinatorShutdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Coordinator,
        [ValidateRange(0, 30000)][int]$WaitMilliseconds = 5000,
        [switch]$CancelCooperativeOperations
    )

    $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        $Coordinator.AcceptingOperations = $false
        $Coordinator.ShutdownRequested = $true
    }

    Update-SisqualOperationCoordinator -Coordinator $Coordinator

    if ($CancelCooperativeOperations) {
        $ids = @(Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            return @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) -and $_.CancellationMode -eq 'COOPERATIVE' } | ForEach-Object { $_.OperationId })
        })
        foreach ($id in $ids) {
            $null = Request-SisqualOperationCancellation -OperationId $id -Coordinator $Coordinator
        }
    }

    $deadline = [DateTime]::UtcNow.AddMilliseconds($WaitMilliseconds)
    do {
        Update-SisqualOperationCoordinator -Coordinator $Coordinator
        $active = @(Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            return @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) } | ForEach-Object { $_.OperationId })
        })
        if ($active.Count -eq 0) {
            return [pscustomobject]@{ ReadyToExit = $true; ActiveOperationIds = @(); ShutdownRequested = $true }
        }
        if ([DateTime]::UtcNow -ge $deadline) {
            return [pscustomobject]@{ ReadyToExit = $false; ActiveOperationIds = $active; ShutdownRequested = $true }
        }
        Start-Sleep -Milliseconds 25
    } while ($true)
}

function Close-SisqualOperationCoordinator {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Coordinator)

    Update-SisqualOperationCoordinator -Coordinator $Coordinator
    $active = @(Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        return @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) } | ForEach-Object { $_.OperationId })
    })

    if ($active.Count -gt 0) {
        throw "Cannot close coordinator while operations are active: $($active -join ',')"
    }

    $null = Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        $Coordinator.AcceptingOperations = $false
        $Coordinator.Closed = $true
    }

    $Coordinator.RunspacePool.Close()
    $Coordinator.RunspacePool.Dispose()
}

Export-ModuleMember -Function @(
    'New-SisqualOperationCoordinator',
    'Start-SisqualOperation',
    'Get-SisqualOperation',
    'Request-SisqualOperationCancellation',
    'Request-SisqualCoordinatorShutdown',
    'Close-SisqualOperationCoordinator',
    'Update-SisqualOperationCoordinator'
)
