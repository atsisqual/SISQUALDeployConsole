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
        & $ScriptBlock
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

    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        foreach ($operation in @($Coordinator.Operations.Values)) {
            if ((Test-TerminalStatus -Status $operation.Status) -or $null -eq $operation.AsyncResult) {
                continue
            }

            if ($operation.AsyncResult.IsCompleted) {
                $completed.Add($operation)
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

        Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
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
    $result = $null
    $operation = $null

    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if ($Coordinator.Closed) {
            $result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'COORDINATOR_CLOSED'; OperationId = $null; BlockingOperationId = $null }
            return
        }

        if ($Coordinator.Idempotency.ContainsKey($IdempotencyKey)) {
            $existing = $Coordinator.Idempotency[$IdempotencyKey]
            if ([string]$existing.RequestFingerprint -eq $requestFingerprint) {
                $result = [pscustomobject]@{ Accepted = $true; Reused = $true; Reason = 'IDEMPOTENT_REPLAY'; OperationId = [string]$existing.OperationId; BlockingOperationId = $null }
            }
            else {
                $result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'IDEMPOTENCY_CONFLICT'; OperationId = [string]$existing.OperationId; BlockingOperationId = $null }
            }
            return
        }

        if (-not $Coordinator.AcceptingOperations) {
            $result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'SHUTTING_DOWN'; OperationId = $null; BlockingOperationId = $null }
            return
        }

        foreach ($lockKey in $canonicalLocks) {
            if ($Coordinator.Locks.ContainsKey($lockKey)) {
                $result = [pscustomobject]@{ Accepted = $false; Reused = $false; Reason = 'LOCK_CONFLICT'; OperationId = $null; BlockingOperationId = [string]$Coordinator.Locks[$lockKey]; LockKey = $lockKey }
                return
            }
        }

        $operationId = [guid]::NewGuid().ToString('D')
        $cancellationSource = [Threading.CancellationTokenSource]::new()
        $operation = [pscustomobject][ordered]@{
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

        $Coordinator.Operations.Add($operationId, $operation)
        $Coordinator.Idempotency.Add($IdempotencyKey, [pscustomobject]@{ OperationId = $operationId; RequestFingerprint = $requestFingerprint })
        foreach ($lockKey in $canonicalLocks) {
            $Coordinator.Locks.Add($lockKey, $operationId)
        }
    }

    if ($null -ne $result) {
        return $result
    }

    $powerShell = [PowerShell]::Create()
    $powerShell.RunspacePool = $Coordinator.RunspacePool
    $null = $powerShell.AddScript($WorkerScript.ToString())
    $null = $powerShell.AddArgument($operation.OperationId)
    $null = $powerShell.AddArgument($operation.CancellationSource.Token)
    $null = $powerShell.AddArgument($WorkerArgument)

    try {
        $asyncResult = $powerShell.BeginInvoke()
        Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $operation.PowerShell = $powerShell
            $operation.AsyncResult = $asyncResult
            $operation.Status = 'RUNNING'
            $operation.StartedAt = [DateTime]::UtcNow
        }
    }
    catch {
        Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $operation.Status = 'FAILED'
            $operation.FinishedAt = [DateTime]::UtcNow
            $operation.ErrorType = $_.Exception.GetType().FullName
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
    $snapshot = $null
    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if (-not $Coordinator.Operations.ContainsKey($OperationId)) {
            return
        }
        $operation = $Coordinator.Operations[$OperationId]
        $snapshot = [pscustomobject][ordered]@{
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
    return $snapshot
}

function Request-SisqualOperationCancellation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)]$Coordinator
    )

    Update-SisqualOperationCoordinator -Coordinator $Coordinator
    $result = $null
    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        if (-not $Coordinator.Operations.ContainsKey($OperationId)) {
            $result = [pscustomobject]@{ Accepted = $false; Reason = 'NOT_FOUND'; OperationId = $OperationId }
            return
        }

        $operation = $Coordinator.Operations[$OperationId]
        if (Test-TerminalStatus -Status $operation.Status) {
            $result = [pscustomobject]@{ Accepted = $true; Reason = 'ALREADY_FINISHED'; OperationId = $OperationId }
            return
        }

        if ($operation.CancellationMode -ne 'COOPERATIVE') {
            $result = [pscustomobject]@{ Accepted = $false; Reason = 'NOT_CANCELLABLE'; OperationId = $OperationId }
            return
        }

        if (-not $operation.CancellationRequested) {
            $operation.CancellationRequested = $true
            $operation.Status = 'CANCELLING'
            $operation.CancellationSource.Cancel()
        }
        $result = [pscustomobject]@{ Accepted = $true; Reason = 'CANCELLATION_REQUESTED'; OperationId = $OperationId }
    }
    return $result
}

function Request-SisqualCoordinatorShutdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Coordinator,
        [ValidateRange(0, 30000)][int]$WaitMilliseconds = 5000,
        [switch]$CancelCooperativeOperations
    )

    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        $Coordinator.AcceptingOperations = $false
        $Coordinator.ShutdownRequested = $true
    }

    Update-SisqualOperationCoordinator -Coordinator $Coordinator

    if ($CancelCooperativeOperations) {
        $ids = @()
        Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $ids = @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) -and $_.CancellationMode -eq 'COOPERATIVE' } | ForEach-Object { $_.OperationId })
        }
        foreach ($id in $ids) {
            $null = Request-SisqualOperationCancellation -OperationId $id -Coordinator $Coordinator
        }
    }

    $deadline = [DateTime]::UtcNow.AddMilliseconds($WaitMilliseconds)
    do {
        Update-SisqualOperationCoordinator -Coordinator $Coordinator
        $active = @()
        Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
            $active = @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) } | ForEach-Object { $_.OperationId })
        }
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
    $active = @()
    Invoke-WithCoordinatorLock -Coordinator $Coordinator -ScriptBlock {
        $active = @($Coordinator.Operations.Values | Where-Object { -not (Test-TerminalStatus -Status $_.Status) } | ForEach-Object { $_.OperationId })
        if ($active.Count -eq 0) {
            $Coordinator.AcceptingOperations = $false
            $Coordinator.Closed = $true
        }
    }

    if ($active.Count -gt 0) {
        throw "Cannot close coordinator while operations are active: $($active -join ',')"
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
