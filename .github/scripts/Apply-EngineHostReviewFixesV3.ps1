#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Replace-Exact {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw ("{0}: expected exactly once, found {1}" -f $Label,$count) }
    return $Text.Replace($Old,$New)
}

$utf8 = [Text.UTF8Encoding]::new($false)
$modulePath = 'runtime/Sisqual.Runtime.EngineHost.psm1'
$m = [IO.File]::ReadAllText($modulePath)

# Verify the exact catalog member from the sealed package manifest before every launch.
$old = @'
function ConvertTo-SisqualCanonicalString {
'@
$new = @'
function Get-SisqualVerifiedCatalogPath {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][object[]]$ManifestEntries
    )

    if (-not [IO.Path]::IsPathFullyQualified($PackageRoot)) { throw 'PACKAGE_ROOT_NOT_ABSOLUTE' }
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $catalogEntries = @($ManifestEntries | Where-Object {
        $candidate = [string](Get-SisqualMemberValue $_ 'path' '')
        $candidate -cmatch '^catalog/catalog-[A-Za-z0-9_-]{1,60}\.db$'
    })
    if ($catalogEntries.Count -ne 1) { throw 'CATALOG_MANIFEST_ENTRY_INVALID' }

    $entry = $catalogEntries[0]
    $relativePath = [string](Get-SisqualMemberValue $entry 'path' '')
    $expectedHash = [string](Get-SisqualMemberValue $entry 'sha256' '')
    if ($expectedHash -cnotmatch '^[0-9a-f]{64}$') { throw 'CATALOG_MANIFEST_ENTRY_INVALID' }

    $expectedPath = [IO.Path]::GetFullPath((Join-Path $root ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))))
    $providedPath = if ([IO.Path]::IsPathFullyQualified($CatalogPath)) {
        [IO.Path]::GetFullPath($CatalogPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $root $CatalogPath))
    }
    if (-not $providedPath.Equals($expectedPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_PATH_MISMATCH' }
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) { throw 'CATALOG_FILE_MISSING' }
    if ((Get-SisqualSha256Hex $expectedPath) -cne $expectedHash) { throw 'CATALOG_HASH_MISMATCH' }

    $sizeValue = Get-SisqualMemberValue $entry 'size' $null
    if ($null -ne $sizeValue) {
        $expectedSize = [long]$sizeValue
        if ($expectedSize -lt 0 -or (Get-Item -LiteralPath $expectedPath).Length -ne $expectedSize) { throw 'CATALOG_SIZE_MISMATCH' }
    }
    return $expectedPath
}

function ConvertTo-SisqualCanonicalString {
'@
$m = Replace-Exact $m $old $new 'insert catalog verifier'

# Carry the coordinator lock set into audit records.
$old = @'
        [System.Collections.IDictionary]$Secrets = @{},
        [string]$OperationId = ([guid]::NewGuid().ToString()),
'@
$new = @'
        [System.Collections.IDictionary]$Secrets = @{},
        [string[]]$LockKeys = @(),
        [string]$OperationId = ([guid]::NewGuid().ToString()),
'@
$m = Replace-Exact $m $old $new 'add LockKeys parameter'

# Fail closed on the action row as well as the engine row.
$old = @'
    if ([int](Get-SisqualMemberValue $Engine 'IsEnabled' 0) -ne 1) { throw 'ENGINE_DISABLED' }

    $actionType = [string](Get-SisqualMemberValue $Action 'ActionType' 'ENGINE')
'@
$new = @'
    if ([int](Get-SisqualMemberValue $Engine 'IsEnabled' 0) -ne 1) { throw 'ENGINE_DISABLED' }
    if ([int](Get-SisqualMemberValue $Action 'IsEnabled' 0) -ne 1) { throw 'ACTION_DISABLED' }
    $actionEngineCode = [string](Get-SisqualMemberValue $Action 'EngineCode' '')
    if ($actionEngineCode -cne $engineCode) { throw 'ACTION_ENGINE_MISMATCH' }

    $actionType = [string](Get-SisqualMemberValue $Action 'ActionType' 'ENGINE')
'@
$m = Replace-Exact $m $old $new 'add action guards'

$old = @'
    if (-not [string]::Equals($CatalogMachineName, $env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }

    $engineLeaf = [string](Get-SisqualMemberValue $Engine 'SourceFileName' '')
'@
$new = @'
    if (-not [string]::Equals($CatalogMachineName, $env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }
    $CatalogPath = Get-SisqualVerifiedCatalogPath -PackageRoot $PackageRoot -CatalogPath $CatalogPath -ManifestEntries $ManifestEntries
    [string[]]$normalizedLocks = @($LockKeys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)

    $engineLeaf = [string](Get-SisqualMemberValue $Engine 'SourceFileName' '')
'@
$m = Replace-Exact $m $old $new 'verify catalog and normalize locks'

# Async stdin delivery is monitored by the same deadline as the child process.
$old = @'
        $process.StandardInput.Write($requestJson); $process.StandardInput.Close()

        $completed = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $completed) {
            [IO.File]::WriteAllText($cancelPath, 'cancel', [Text.UTF8Encoding]::new($false))
            $completed = $process.WaitForExit([Math]::Max(1, $CancellationGraceSeconds) * 1000)
            if (-not $completed) {
                if ($EngineClass -ceq 'MUTATING') {
                    $keepRunDirectory = $true
                    $script:TimedOutProcesses[$OperationId] = [pscustomobject]@{ Process = $process; RunDirectory = $runDirectory; StdoutTask = $stdoutTask; StderrTask = $stderrTask }
                    return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'TIMED_OUT_RUNNING' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets
                }
                $process.Kill($true); $process.WaitForExit()
            }
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult(); $exitCode = $process.ExitCode
'@
$new = @'
        $deadlineAt = $started.AddSeconds($timeoutSeconds)
        $stdinTask = $process.StandardInput.WriteAsync($requestJson)
        $stdinClosed = $false
        $stdinWriteFailed = $false
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadlineAt) {
            if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                try { $stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                catch { $stdinWriteFailed = $true }
                $stdinClosed = $true
            }
            Start-Sleep -Milliseconds 10
        }
        $completed = $process.HasExited
        if (-not $completed) {
            [IO.File]::WriteAllText($cancelPath, 'cancel', [Text.UTF8Encoding]::new($false))
            $graceDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $CancellationGraceSeconds))
            while (-not $process.HasExited -and [DateTime]::UtcNow -lt $graceDeadline) {
                if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                    try { $stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                    catch { $stdinWriteFailed = $true }
                    $stdinClosed = $true
                }
                Start-Sleep -Milliseconds 10
            }
            $completed = $process.HasExited
            if (-not $completed) {
                if ($EngineClass -ceq 'MUTATING') {
                    $keepRunDirectory = $true
                    $script:TimedOutProcesses[$OperationId] = [pscustomobject]@{ Process = $process; RunDirectory = $runDirectory; StdinTask = $stdinTask; StdoutTask = $stdoutTask; StderrTask = $stderrTask }
                    return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'TIMED_OUT_RUNNING' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
                }
                $process.Kill($true); $process.WaitForExit()
            }
        }
        if (-not $stdinClosed) {
            if ($stdinTask.IsCompleted) {
                try { $stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                catch { $stdinWriteFailed = $true }
            }
            else {
                $stdinWriteFailed = $true
                try { $process.StandardInput.Close() } catch { }
            }
            $stdinClosed = $true
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult(); $exitCode = $process.ExitCode
        if ($stdinWriteFailed) {
            return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
'@
$m = Replace-Exact $m $old $new 'replace blocking stdin and timeout block'

# Extend the failure helper with safe audit context.
$old = @'
        [datetime]$StartedAt = ([DateTime]::UtcNow),
        [System.Collections.IDictionary]$Secrets = @{}
    )
    $result = New-SisqualEngineFailureResult $OperationId $EngineCode $Mode $ErrorCode $EngineVersion $ExitCode
    Write-SisqualEngineHostLog -EventCode 'ENGINE.FAIL' -Message 'Engine run failed.' -Properties @{
        operationId = $OperationId; engine = $EngineCode; mode = $Mode
        durationMs = [int]([DateTime]::UtcNow - $StartedAt).TotalMilliseconds
        exitCode = $ExitCode; succeeded = $false; error = $ErrorCode
    } -Secrets $Secrets
'@
$new = @'
        [datetime]$StartedAt = ([DateTime]::UtcNow),
        [System.Collections.IDictionary]$Secrets = @{},
        [AllowNull()][string]$PlanFingerprint,
        [string[]]$LockKeys = @()
    )
    $result = New-SisqualEngineFailureResult $OperationId $EngineCode $Mode $ErrorCode $EngineVersion $ExitCode
    Write-SisqualEngineHostLog -EventCode 'ENGINE.FAIL' -Message 'Engine run failed.' -Properties @{
        operationId = $OperationId; engine = $EngineCode; mode = $Mode
        durationMs = [int]([DateTime]::UtcNow - $StartedAt).TotalMilliseconds
        exitCode = $ExitCode; succeeded = $false; error = $ErrorCode
        planFingerprint = [string]$PlanFingerprint; locks = (@($LockKeys) -join ',')
        targetCount = [int]$result.summary.targetCount; succeededTargets = [int]$result.summary.succeededTargets
        failedTargets = [int]$result.summary.failedTargets; warningCount = [int]$result.summary.warningCount; errorCount = [int]$result.summary.errorCount
    } -Secrets $Secrets
'@
$m = Replace-Exact $m $old $new 'extend failure audit helper'

# Add context to all other synthesized post-launch failures.
$m = $m.Replace('-StartedAt $started -Secrets $Secrets','-StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks')
$m = $m.Replace('-PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks','-PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks')

$old = @'
        Write-SisqualEngineHostLog -EventCode 'ENGINE.COMPLETE' -Message 'Engine run completed.' -Properties @{ operationId = $OperationId; engine = $engineCode; mode = $Mode; instance = [string]$InstanceCode; durationMs = [int]([DateTime]::UtcNow - $started).TotalMilliseconds; exitCode = $exitCode; succeeded = [bool]$result.succeeded } -Secrets $Secrets
'@
$new = @'
        $auditPlanFingerprint = if ($null -ne $result.PSObject.Properties['planFingerprint']) { [string]$result.planFingerprint } else { [string]$PlanFingerprint }
        Write-SisqualEngineHostLog -EventCode 'ENGINE.COMPLETE' -Message 'Engine run completed.' -Properties @{
            operationId = $OperationId; engine = $engineCode; mode = $Mode; instance = [string]$InstanceCode
            durationMs = [int]([DateTime]::UtcNow - $started).TotalMilliseconds; exitCode = $exitCode; succeeded = [bool]$result.succeeded
            planFingerprint = $auditPlanFingerprint; locks = (@($normalizedLocks) -join ',')
            targetCount = [int]$result.summary.targetCount; succeededTargets = [int]$result.summary.succeededTargets
            failedTargets = [int]$result.summary.failedTargets; warningCount = [int]$result.summary.warningCount; errorCount = [int]$result.summary.errorCount
        } -Secrets $Secrets
'@
$m = Replace-Exact $m $old $new 'extend completion audit event'
[IO.File]::WriteAllText($modulePath,$m,$utf8)

# Main host test fixture: real sealed catalog layout and action mapping.
$testPath = 'tests/EngineHost/Test-EngineHost.ps1'
$t = [IO.File]::ReadAllText($testPath)
$old = @'
    $catalogPath = Join-Path $root 'catalog.sqlite'
    [IO.File]::WriteAllText($catalogPath, 'synthetic-catalog', [Text.UTF8Encoding]::new($false))
'@
$new = @'
    $catalogDir = Join-Path $root 'catalog'
    [void][IO.Directory]::CreateDirectory($catalogDir)
    $catalogPath = Join-Path $catalogDir 'catalog-TEST.db'
    [IO.File]::WriteAllText($catalogPath, 'synthetic-catalog', [Text.UTF8Encoding]::new($false))
'@
$t = Replace-Exact $t $old $new 'host fixture catalog path'
$old = @'
    $action = [pscustomobject]@{
        ActionType = 'ENGINE'
'@
$new = @'
    $action = [pscustomobject]@{
        ActionCode = 'FAKE_ACTION'
        EngineCode = 'FAKE_ENGINE'
        IsEnabled = 1
        ActionType = 'ENGINE'
'@
$t = Replace-Exact $t $old $new 'host fixture action mapping'
$old = @'
    $manifest = @([pscustomobject]@{ path = ('engines/' + $LeafName); sha256 = Get-FileSha256 -Path $enginePath })
'@
$new = @'
    $manifest = @(
        [pscustomobject]@{ path = ('engines/' + $LeafName); sha256 = Get-FileSha256 -Path $enginePath },
        [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = Get-FileSha256 -Path $catalogPath; size = (Get-Item -LiteralPath $catalogPath).Length }
    )
'@
$t = Replace-Exact $t $old $new 'host fixture catalog manifest'
$old = @'
    return Invoke-SisqualEngineHost -Engine $Context.Engine -Action $Context.Action -EngineClass $Context.Class -PackageRoot $Context.Root -CatalogPath $Context.Catalog -CatalogMachineName $env:COMPUTERNAME -ManifestEntries $Context.Manifest -Mode $Mode -InstanceCode $Context.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $ConfirmationText -Secrets $Secrets -CancellationGraceSeconds 2
'@
$new = @'
    return Invoke-SisqualEngineHost -Engine $Context.Engine -Action $Context.Action -EngineClass $Context.Class -PackageRoot $Context.Root -CatalogPath $Context.Catalog -CatalogMachineName $env:COMPUTERNAME -ManifestEntries $Context.Manifest -Mode $Mode -InstanceCode $Context.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $ConfirmationText -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Context.Scenario) -CancellationGraceSeconds 2
'@
$t = Replace-Exact $t $old $new 'host wrapper lock context'
$old = @'
    $killable = New-TestContext -Scenario 'HANG_IGNORE' -TimeoutSeconds 1
'@
$new = @'
    $asyncInput = New-TestContext -TimeoutSeconds 1
    $env:SISQUAL_FAKE_ENGINE_DELAY_STDIN_MS = '6000'
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TestHost -Context $asyncInput -Secrets @{ BULK = ('Z' * 262144) }
        $watch.Stop()
        Check 'large stdin cannot block timeout enforcement' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 5) ([string]$result.errorMessage)
    }
    finally { Remove-Item Env:\SISQUAL_FAKE_ENGINE_DELAY_STDIN_MS -ErrorAction SilentlyContinue }

    $killable = New-TestContext -Scenario 'HANG_IGNORE' -TimeoutSeconds 1
'@
$t = Replace-Exact $t $old $new 'async stdin regression'
[IO.File]::WriteAllText($testPath,$t,$utf8)

# Mutation fixture: same catalog/action invariants plus focused failures.
$mutationPath = 'tests/EngineHost/Test-EngineHostMutations.ps1'
$t = [IO.File]::ReadAllText($mutationPath)
$old = @'
    $catalog = Join-Path $root 'catalog.sqlite'; Set-Content -LiteralPath $catalog -Value 'synthetic' -NoNewline -Encoding ascii
'@
$new = @'
    $catalogDir = Join-Path $root 'catalog'; [void][IO.Directory]::CreateDirectory($catalogDir)
    $catalog = Join-Path $catalogDir 'catalog-TEST.db'; Set-Content -LiteralPath $catalog -Value 'synthetic' -NoNewline -Encoding ascii
'@
$t = Replace-Exact $t $old $new 'mutation fixture catalog path'
$old = @'
        Action = [pscustomobject]@{ ActionType = 'ENGINE'; ModePolicy = $ModePolicy; RequiresInstanceSelection = 1; AllowAllInstances = 1; InstanceSelectionPolicy = 'ALL_ENABLED'; PassInstanceCode = 1; PassApply = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 1 } else { 0 }); ConfirmationText = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 'CONFIRM' } else { '' }); CommandTimeoutSeconds = 5 }
        Manifest = @([pscustomobject]@{ path = ('engines/' + $leaf); sha256 = $hash })
'@
$new = @'
        Action = [pscustomobject]@{ ActionCode = 'FAKE_ACTION'; EngineCode = 'FAKE_ENGINE'; IsEnabled = 1; ActionType = 'ENGINE'; ModePolicy = $ModePolicy; RequiresInstanceSelection = 1; AllowAllInstances = 1; InstanceSelectionPolicy = 'ALL_ENABLED'; PassInstanceCode = 1; PassApply = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 1 } else { 0 }); ConfirmationText = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 'CONFIRM' } else { '' }); CommandTimeoutSeconds = 5 }
        Manifest = @(
            [pscustomobject]@{ path = ('engines/' + $leaf); sha256 = $hash },
            [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant(); size = (Get-Item -LiteralPath $catalog).Length }
        )
'@
$t = Replace-Exact $t $old $new 'mutation fixture action and manifest'
$old = @'
    Invoke-SisqualEngineHost -Engine $Ctx.Engine -Action $Ctx.Action -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogMachineName $MachineName -ManifestEntries $Ctx.Manifest -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -CancellationGraceSeconds 1
'@
$new = @'
    Invoke-SisqualEngineHost -Engine $Ctx.Engine -Action $Ctx.Action -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogMachineName $MachineName -ManifestEntries $Ctx.Manifest -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Ctx.Scenario) -CancellationGraceSeconds 1
'@
$t = Replace-Exact $t $old $new 'mutation wrapper lock context'
$old = @'
    $ctx = New-Ctx; $ctx.Engine.IsEnabled = 0
    Check 'mutation: disabled engine is rejected' (Throws-Code { Run $ctx } 'ENGINE_DISABLED')
'@
$new = @'
    $ctx = New-Ctx; $ctx.Engine.IsEnabled = 0
    Check 'mutation: disabled engine is rejected' (Throws-Code { Run $ctx } 'ENGINE_DISABLED')

    $ctx = New-Ctx; $ctx.Action.IsEnabled = 0
    Check 'mutation: disabled action is rejected' (Throws-Code { Run $ctx } 'ACTION_DISABLED')

    $ctx = New-Ctx; $ctx.Action.EngineCode = 'OTHER_ENGINE'
    Check 'mutation: action engine mapping is exact' (Throws-Code { Run $ctx } 'ACTION_ENGINE_MISMATCH')

    $ctx = New-Ctx; $rogue = Join-Path $ctx.Root 'other.db'; Set-Content -LiteralPath $rogue -Value 'synthetic' -NoNewline -Encoding ascii; $ctx.Catalog = $rogue
    Check 'mutation: arbitrary catalog path is rejected' (Throws-Code { Run $ctx } 'CATALOG_PATH_MISMATCH')

    $ctx = New-Ctx; Add-Content -LiteralPath $ctx.Catalog -Value 'tamper' -NoNewline -Encoding ascii
    Check 'mutation: catalog hash is reverified before launch' (Throws-Code { Run $ctx } 'CATALOG_HASH_MISMATCH')
'@
$t = Replace-Exact $t $old $new 'action/catalog mutation cases'
$old = @'
    Check 'mutation: failed completion is audit logged' ($failureLog.Contains('ENGINE.FAIL',[StringComparison]::Ordinal) -and $failureLog.Contains('operationId',[StringComparison]::Ordinal) -and $failureLog.Contains('ENGINE_NO_RESULT',[StringComparison]::Ordinal))

    $ctx = New-Ctx -Scenario 'UNEXPECTED_EXIT'; $result = Run $ctx
'@
$new = @'
    Check 'mutation: failed completion is audit logged' ($failureLog.Contains('ENGINE.FAIL',[StringComparison]::Ordinal) -and $failureLog.Contains('operationId',[StringComparison]::Ordinal) -and $failureLog.Contains('ENGINE_NO_RESULT',[StringComparison]::Ordinal) -and $failureLog.Contains('planFingerprint',[StringComparison]::Ordinal) -and $failureLog.Contains('locks',[StringComparison]::Ordinal) -and $failureLog.Contains('targetCount',[StringComparison]::Ordinal))

    if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { Remove-Item -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Force }
    $ctx = New-Ctx; $result = Run $ctx
    $completionLog = if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { [IO.File]::ReadAllText($env:SISQUAL_ENGINEHOST_TEST_LOG) } else { '' }
    Check 'mutation: completion audit carries plan locks and summary' ($completionLog.Contains('planFingerprint',[StringComparison]::Ordinal) -and $completionLog.Contains('locks',[StringComparison]::Ordinal) -and $completionLog.Contains('targetCount',[StringComparison]::Ordinal) -and $completionLog.Contains('failedTargets',[StringComparison]::Ordinal) -and $completionLog.Contains('errorCount',[StringComparison]::Ordinal))

    $ctx = New-Ctx -Scenario 'UNEXPECTED_EXIT'; $result = Run $ctx
'@
$t = Replace-Exact $t $old $new 'audit mutation cases'
[IO.File]::WriteAllText($mutationPath,$t,$utf8)

# Fake engine can delay reading stdin solely for the timeout mutation.
$fakePath = 'tests/EngineHost/FakeEngine.ps1'
$f = [IO.File]::ReadAllText($fakePath)
$old = @'
$raw = [Console]::In.ReadToEnd()
'@
$new = @'
$delayText = [string]$env:SISQUAL_FAKE_ENGINE_DELAY_STDIN_MS
if ($delayText -match '^\d{1,5}$') { Start-Sleep -Milliseconds ([Math]::Min([int]$delayText,15000)) }
$raw = [Console]::In.ReadToEnd()
'@
$f = Replace-Exact $f $old $new 'fake delayed stdin control'
[IO.File]::WriteAllText($fakePath,$f,$utf8)

# Mutation anchors prove the four review guards remain live.
$sourcePath = 'tests/EngineHost/Test-EngineHostSourceMutations.ps1'
$s = [IO.File]::ReadAllText($sourcePath)
$old = @'
    [pscustomobject]@{ Name = 'failed completion audit helper'; Text = 'function New-SisqualLoggedEngineFailureResult' }
'@
$new = @'
    [pscustomobject]@{ Name = 'failed completion audit helper'; Text = 'function New-SisqualLoggedEngineFailureResult' },
    [pscustomobject]@{ Name = 'async stdin write'; Text = 'StandardInput.WriteAsync($requestJson)' },
    [pscustomobject]@{ Name = 'catalog path verification'; Text = 'Get-SisqualVerifiedCatalogPath -PackageRoot' },
    [pscustomobject]@{ Name = 'action enabled guard'; Text = "throw 'ACTION_DISABLED'" },
    [pscustomobject]@{ Name = 'action engine mapping guard'; Text = "throw 'ACTION_ENGINE_MISMATCH'" },
    [pscustomobject]@{ Name = 'completion summary audit'; Text = 'targetCount = [int]$result.summary.targetCount' }
'@
$s = Replace-Exact $s $old $new 'source mutation anchors'
[IO.File]::WriteAllText($sourcePath,$s,$utf8)

foreach ($file in @($modulePath,$testPath,$mutationPath,$fakePath,$sourcePath)) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file).Path,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -gt 0) { throw ("Parse failed in {0}: {1}" -f $file,$errors[0].Message) }
}

foreach ($suite in @(
    'tests/EngineHost/Test-FakeEngineDirect.ps1',
    'tests/EngineHost/Test-EngineHostFingerprints.ps1',
    'tests/EngineHost/Test-EngineHost.ps1',
    'tests/EngineHost/Test-EngineHostMutations.ps1',
    'tests/EngineHost/Test-EngineHostSourceMutations.ps1'
)) {
    & pwsh -NoLogo -NoProfile -NonInteractive -File $suite
    if ($LASTEXITCODE -ne 0) { throw ("Focused suite failed: {0}" -f $suite) }
}

Remove-Item '.github/workflows/apply-enginehost-review-fixes-v3.yml' -Force -ErrorAction SilentlyContinue
Remove-Item '.github/scripts/Apply-EngineHostReviewFixesV3.ps1' -Force -ErrorAction SilentlyContinue

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add -A
git diff --cached --check
git commit -m 'runtime: close final engine host review gaps'
git push origin HEAD:engine-host/adr-0008-runtime
