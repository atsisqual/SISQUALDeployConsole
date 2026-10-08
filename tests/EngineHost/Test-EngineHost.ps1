#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
. (Join-Path $PSScriptRoot 'TestCatalogSessionStub.ps1')
Initialize-SisqualEngineHostCatalogStub

$env:SISQUAL_ENGINEHOST_TEST_LOG = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-contract-log-' + [guid]::NewGuid().ToString('N') + '.jsonl')
function global:Write-SisqualRuntimeLog {
    param([string]$Level,[string]$EventCode,[string]$Message,[hashtable]$Properties)
    $entry = [ordered]@{ level = $Level; eventCode = $EventCode; message = $Message; properties = $Properties }
    Add-Content -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding utf8
    return $env:SISQUAL_ENGINEHOST_TEST_LOG
}
$script:LauncherHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'runtime' 'Invoke-SisqualEngineLauncher.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
$script:Passed = 0
$script:Failed = 0
$script:TempRoots = [Collections.Generic.List[string]]::new()

function Show-HostLogTail {
    if ($env:SISQUAL_ENGINEHOST_TEST_LOG -and (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG)) {
        foreach ($line in @(Get-Content -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Tail 3)) { Write-Host ('      host log: ' + $line) }
    }
}

function Check {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host ('PASS  ' + $Name)
    }
    else {
        $script:Failed++
        Write-Host ('FAIL  ' + $Name + $(if ($Detail) { ' - ' + $Detail } else { '' }))
        Show-HostLogTail
    }
}

function Throws-Code {
    param([scriptblock]$Script, [string]$Code)
    try { & $Script | Out-Null; return $false }
    catch { return $_.Exception.Message -ceq $Code }
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-TestContext {
    param(
        [string]$Scenario = 'GOOD',
        [string]$ModePolicy = 'NONE',
        [string]$EngineClass = 'READ_ONLY',
        [int]$TimeoutSeconds = 5,
        [string]$LeafName = 'Odd-Engine-Name.ps1'
    )
    $root = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-test-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'engines'))
    $script:TempRoots.Add($root)
    $source = Join-Path $PSScriptRoot 'FakeEngine.ps1'
    $enginePath = Join-Path (Join-Path $root 'engines') $LeafName
    Copy-Item -LiteralPath $source -Destination $enginePath
    $catalogDir = Join-Path $root 'catalog'
    [void][IO.Directory]::CreateDirectory($catalogDir)
    $catalogPath = Join-Path $catalogDir 'catalog-TEST.db'
    [IO.File]::WriteAllText($catalogPath, 'synthetic-catalog', [Text.UTF8Encoding]::new($false))

    $engine = [pscustomobject]@{
        EngineCode = 'FAKE_ENGINE'
        EngineVersion = 'test-1.0'
        SourceFileName = $LeafName
        IsEnabled = 1
        MinimumPowerShell = '7.0'
        RequiresAdministrator = 0
    }
    $action = [pscustomobject]@{
        ActionCode = 'FAKE_ACTION'
        EngineCode = 'FAKE_ENGINE'
        IsEnabled = 1
        ActionType = 'ENGINE'
        ModePolicy = $ModePolicy
        RequiresInstanceSelection = 1
        AllowAllInstances = 1
        InstanceSelectionPolicy = 'ALL_ENABLED'
        PassInstanceCode = 1
        PassApply = if ($ModePolicy -ceq 'PREVIEW_APPLY') { 1 } else { 0 }
        ConfirmationText = if ($ModePolicy -ceq 'PREVIEW_APPLY') { 'CONFIRM' } else { '' }
        CommandTimeoutSeconds = $TimeoutSeconds
    }
    $manifest = @(
        [pscustomobject]@{ path = ('engines/' + $LeafName); sha256 = Get-FileSha256 -Path $enginePath },
        [pscustomobject]@{ path = 'runtime/Invoke-SisqualEngineLauncher.ps1'; sha256 = $script:LauncherHash },
        [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = Get-FileSha256 -Path $catalogPath; size = (Get-Item -LiteralPath $catalogPath).Length }
    )
    $built = [pscustomobject]@{
        Root = $root
        Catalog = $catalogPath
        Engine = $engine
        Action = $action
        Manifest = $manifest
        CatalogSession = (New-SisqualTestCatalogSession -CatalogPath $catalogPath -MachineName ([Environment]::MachineName))
        Class = $EngineClass
        Scenario = $Scenario
    }
    Set-SisqualTestCatalogRows -Session $built.CatalogSession -Engine $built.Engine -Action $built.Action
    return $built
}

function Get-ManifestWithSecretContract {
    # The credential references an engine may receive come from the package contract, which is in the manifest like every other file.
    param([Parameter(Mandatory)][object]$Context, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Declared)
    $dir = Join-Path $Context.Root 'contracts'; [void][IO.Directory]::CreateDirectory($dir)
    $path = Join-Path $dir 'engine-secret-references.json'
    [IO.File]::WriteAllText($path, ([ordered]@{ contractVersion = '0.1-proposed'; engines = [ordered]@{ FAKE_ENGINE = @($Declared) } } | ConvertTo-Json -Depth 5 -Compress), [Text.UTF8Encoding]::new($false))
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    return @(@($Context.Manifest | Where-Object { $_.path -cne 'contracts/engine-secret-references.json' }) + [pscustomobject]@{ path = 'contracts/engine-secret-references.json'; sha256 = $hash })
}

function Invoke-TestHost {
    param(
        [object]$Context,
        [string]$Mode = 'PREVIEW',
        [string]$PlanFingerprint = $null,
        [string]$ConfirmationText = $null,
        [hashtable]$Secrets = @{},
        [string[]]$Declared = $null,
        [string]$Instance = $null
    )
    if ($null -eq $Declared) { $Declared = @($Secrets.Keys | ForEach-Object { [string]$_ }) }
    $manifestForCall = if ($Secrets.Count -gt 0) { Get-ManifestWithSecretContract -Context $Context -Declared $Declared } else { $Context.Manifest }
    return Invoke-SisqualEngineHost -ActionCode $Context.Action.ActionCode -EngineClass $Context.Class -PackageRoot $Context.Root -CatalogPath $Context.Catalog -CatalogSession $Context.CatalogSession -ManifestEntries $manifestForCall -Mode $Mode -InstanceCode $(if ($PSBoundParameters.ContainsKey('Instance')) { $Instance } else { $Context.Scenario }) -PlanFingerprint $PlanFingerprint -ConfirmationText $ConfirmationText -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Context.Scenario) -CancellationGraceSeconds 2
}

try {
    $good = New-TestContext
    $result = Invoke-TestHost -Context $good
    Check 'SourceFileName from catalog is honored' ($result.engineCode -ceq 'FAKE_ENGINE' -and $result.succeeded) ([string]$result.errorMessage)
    Check 'host does not derive target counts from result row count' ($result.summary.targetCount -eq 1 -and @($result.results).Count -eq 2 -and $result.succeeded) ([string]$result.errorMessage)

    $rapidExitStable = $true
    $rapidExitDetail = ''
    for ($iteration = 0; $iteration -lt 8; $iteration++) {
        $rapid = New-TestContext -Scenario ('GOOD_FAST_{0}' -f $iteration)
        $rapidResult = Invoke-TestHost -Context $rapid
        if (-not $rapidResult.succeeded -or -not [string]::IsNullOrEmpty([string]$rapidResult.errorMessage)) {
            $rapidExitStable = $false
            $rapidExitDetail = [string]$rapidResult.errorMessage
            break
        }
    }
    Check 'rapid successful child exits do not race stdin delivery' $rapidExitStable $rapidExitDetail

    $foreignMachine = New-TestContext
    Set-SisqualTestCatalogMachineName -Session $foreignMachine.CatalogSession -MachineName 'NOT-THIS-MACHINE'
    $foreignMachine.CatalogSession | Add-Member -NotePropertyName MachineName -NotePropertyValue ([Environment]::MachineName) -Force
    Check 'machine ownership is read from active catalog session, not caller properties' (Throws-Code { Invoke-TestHost -Context $foreignMachine } 'CATALOG_MACHINE_MISMATCH')

    $argsSafe = New-TestContext -Scenario 'ARGS_ENV_SAFE'
    $canary = 'CANARY-HOST-9f4d7e1b'
    $result = Invoke-TestHost -Context $argsSafe -Secrets @{ TEST_SECRET = $canary }
    Check 'secret is absent from child arguments and environment' ($result.succeeded -and $result.results[0].details -ceq 'ARGS_ENV_SAFE') ([string]$result.errorMessage)

    foreach ($scenario in @('SECRET_STDOUT','SECRET_STDERR','SECRET_RESULT')) {
        $ctx = New-TestContext -Scenario $scenario
        $result = Invoke-TestHost -Context $ctx -Secrets @{ TEST_SECRET = $canary }
        Check ("secret leak blocked: {0}" -f $scenario) ($result.errorMessage -ceq 'SECRET_LEAK' -and -not $result.succeeded)
    }

    $invalidArithmetic = New-TestContext -Scenario 'INVALID_ARITHMETIC'
    $result = Invoke-TestHost -Context $invalidArithmetic
    Check 'schema arithmetic is validated without row inference' ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')

    $invalidMode = New-TestContext -Scenario 'INVALID_MODE_ECHO'
    $result = Invoke-TestHost -Context $invalidMode
    Check 'result must echo request mode' ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')

    $readOnlyApply = New-TestContext
    Check 'READ_ONLY engine cannot APPLY' (Throws-Code { Invoke-TestHost -Context $readOnlyApply -Mode APPLY } 'READ_ONLY_APPLY_NOT_ALLOWED')

    $sqlAction = New-TestContext
    $sqlAction.Action.ActionType = 'SQL'
    Check 'SQL catalog actions are refused' (Throws-Code { Invoke-TestHost -Context $sqlAction } 'ACTION_TYPE_NOT_SUPPORTED')

    $mutable = New-TestContext -Scenario 'MUTATING' -ModePolicy 'PREVIEW_APPLY' -EngineClass 'MUTATING'
    $preview = Invoke-TestHost -Context $mutable
    $previewFingerprint = if ($null -ne $preview.PSObject.Properties['planFingerprint']) { [string]$preview.planFingerprint } else { '' }
    $previewReady = $preview.succeeded -and $previewFingerprint -match '^[0-9a-f]{64}$'
    Check 'PREVIEW_APPLY preview returns fingerprint' $previewReady ([string]$preview.errorMessage)
    if ($previewReady) {
        $apply = Invoke-TestHost -Context $mutable -Mode APPLY -PlanFingerprint $previewFingerprint -ConfirmationText 'CONFIRM'
        Check 'APPLY accepts fingerprint from same host session' ($apply.succeeded -and $apply.mode -ceq 'APPLY') ([string]$apply.errorMessage)
    }
    else {
        Check 'APPLY accepts fingerprint from same host session' $false ('preview failed: ' + [string]$preview.errorMessage)
    }
    Check 'stale fingerprint is refused before launch' (Throws-Code { Invoke-TestHost -Context $mutable -Mode APPLY -PlanFingerprint ('0' * 64) -ConfirmationText 'CONFIRM' } 'PLAN_CHANGED')

    $childrenA = @(
        [pscustomobject]@{ step = 20; engineCode = 'B_ENGINE'; instanceCode = 'B'; planFingerprint = ('b' * 64) },
        [pscustomobject]@{ step = 10; engineCode = 'A_ENGINE'; instanceCode = 'A'; planFingerprint = ('a' * 64) }
    )
    $childrenB = @($childrenA[1], $childrenA[0])
    $aggregateA = Get-SisqualCompositePlanFingerprint -Children $childrenA
    $aggregateB = Get-SisqualCompositePlanFingerprint -Children $childrenB
    Check 'composite fingerprint is aggregate over ordered child identities' ($aggregateA -ceq $aggregateB -and $aggregateA -match '^[0-9a-f]{64}$')

    $cooperative = New-TestContext -Scenario 'HANG_COOPERATIVE' -TimeoutSeconds 1
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TestHost -Context $cooperative
    $watch.Stop()
    Check 'timeout writes cancel request and cooperative engine exits' ($result.errorMessage -ceq 'CANCELLED' -and $watch.Elapsed.TotalSeconds -lt 8) ([string]$result.errorMessage)

    $asyncInput = New-TestContext -TimeoutSeconds 1
    $delayHook = Join-Path (Join-Path $asyncInput.Root 'engines') 'delay-stdin.ms'
    [IO.File]::WriteAllText($delayHook, '6000')
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TestHost -Context $asyncInput -Secrets @{ BULK = ('Z' * 262144) }
        $watch.Stop()
        Check 'large stdin cannot block timeout enforcement' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 5) ([string]$result.errorMessage)
    }
    finally { Remove-Item -LiteralPath $delayHook -Force -ErrorAction SilentlyContinue }

    $pipeDescendant = New-TestContext -Scenario 'DESCENDANT_PIPE' -TimeoutSeconds 2
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TestHost -Context $pipeDescendant
    $watch.Stop()
    Check 'descendant inheriting redirected pipes cannot block the host' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 6) ([string]$result.errorMessage)

    $killable = New-TestContext -Scenario 'HANG_IGNORE' -TimeoutSeconds 1
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TestHost -Context $killable
    $watch.Stop()
    Check 'non-mutating timed out child is killed after grace' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 8) ([string]$result.errorMessage)
    $startedAt = [datetime]::Parse([string]$result.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    $completedAt = [datetime]::Parse([string]$result.completedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    Check 'a synthesised failure keeps the real start of the run (it is not a zero-length result)' (($completedAt - $startedAt).TotalSeconds -ge 1) (('{0} -> {1}' -f $result.startedAt, $result.completedAt))

    $blocked = New-TestContext -Scenario 'CANCEL_BLOCKED' -TimeoutSeconds 1
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TestHost -Context $blocked
    $watch.Stop()
    Check 'a cancel signal that cannot be written still ends in the timeout handling (read-only engine is killed)' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 10) ([string]$result.errorMessage)

    $blockedMutable = New-TestContext -Scenario 'CANCEL_BLOCKED' -ModePolicy 'PREVIEW_APPLY' -EngineClass 'MUTATING' -TimeoutSeconds 1
    $blockedOperation = [guid]::NewGuid().ToString()
    $result = Invoke-SisqualEngineHost -ActionCode $blockedMutable.Action.ActionCode -EngineClass MUTATING -PackageRoot $blockedMutable.Root -CatalogPath $blockedMutable.Catalog -CatalogSession $blockedMutable.CatalogSession -ManifestEntries $blockedMutable.Manifest -Mode PREVIEW -InstanceCode $blockedMutable.Scenario -LockKeys @('INSTANCE:' + [string]$blockedMutable.Scenario) -OperationId $blockedOperation -CancellationGraceSeconds 1
    Check 'a cancel signal that cannot be written: a mutable engine is retained, not left untracked' ($result.errorMessage -ceq 'TIMED_OUT_RUNNING') ([string]$result.errorMessage)
    [void](Stop-SisqualTimedOutEngineProcess -OperationId $blockedOperation -Confirm:$false)

    # The machine comes from the operating system, not from a variable the caller can change.
    $spoofed = New-TestContext
    Set-SisqualTestCatalogMachineName -Session $spoofed.CatalogSession -MachineName 'SPOOFED-HOST'
    $savedName = $env:COMPUTERNAME; $env:COMPUTERNAME = 'SPOOFED-HOST'
    try { Check 'changing COMPUTERNAME does not make a foreign catalog pass the machine ownership check' (Throws-Code { Invoke-TestHost -Context $spoofed } 'CATALOG_MACHINE_MISMATCH') }
    finally { if ($null -eq $savedName) { Remove-Item Env:\COMPUTERNAME -ErrorAction SilentlyContinue } else { $env:COMPUTERNAME = $savedName } }

    $secretCtx = New-TestContext
    Check 'an undeclared secret is rejected by the host before launch' (Throws-Code { Invoke-TestHost -Context $secretCtx -Secrets @{ TEST_SECRET = 'a'; OTHER_SECRET = 'b' } -Declared @('TEST_SECRET') } 'SECRET_NOT_DECLARED')

    # ADR-0008 item 7: the selected instance is resolved through the verified catalog.
    $instCtx = New-TestContext
    Set-SisqualTestCatalogInstances -Session $instCtx.CatalogSession -Instances @{ GOOD = 1; PT01 = 1; PT02 = 0 }
    Check 'an enabled instance of the catalog is accepted' ([bool](Invoke-TestHost -Context $instCtx -Instance 'PT01').succeeded)
    Check 'an instance that is not in the catalog is rejected before launch' (Throws-Code { Invoke-TestHost -Context $instCtx -Instance 'PT99' } 'INSTANCE_NOT_FOUND')
    Check 'a disabled instance is rejected before launch' (Throws-Code { Invoke-TestHost -Context $instCtx -Instance 'PT02' } 'INSTANCE_DISABLED')
    Check 'an instance code with the wrong shape is rejected before the catalog is asked' (Throws-Code { Invoke-TestHost -Context $instCtx -Instance 'pt01' } 'INSTANCE_INVALID')
    Check 'AllowAllInstances lets the instance stay empty (the engine expands it from the catalog)' ([bool](Invoke-TestHost -Context $instCtx -Instance '').succeeded)
    $noAll = New-TestContext; $noAll.Action.AllowAllInstances = 0
    Check 'without AllowAllInstances an empty instance is still required' (Throws-Code { Invoke-TestHost -Context $noAll -Instance '' } 'INSTANCE_REQUIRED')
    $policyNone = New-TestContext; $policyNone.Action.InstanceSelectionPolicy = 'NONE'
    Check 'an action whose selection policy is NONE refuses a selected instance' (Throws-Code { Invoke-TestHost -Context $policyNone -Instance 'PT01' } 'INSTANCE_SELECTION_NOT_ALLOWED')
    # The engine starts with a minimal environment, not the console's own.
    $env:SISQUAL_TEST_CANARY_ENV = 'canary-env-value'
    try { $envResult = Invoke-TestHost -Context (New-TestContext -Scenario 'ENV_CLEAN') }
    finally { Remove-Item Env:\SISQUAL_TEST_CANARY_ENV -ErrorAction SilentlyContinue }
    Check 'a variable of the console process does not reach the engine' ([bool]$envResult.succeeded -and [string]$envResult.errorMessage -cne 'ENV_LEAK') ([string]$envResult.errorMessage)

    # What the host may kill does not depend on the class the caller declares.
    $mismatch = New-TestContext -ModePolicy 'PREVIEW_APPLY' -EngineClass 'READ_ONLY'
    Check 'an action that can apply cannot be declared READ_ONLY' (Throws-Code { Invoke-TestHost -Context $mismatch } 'ENGINE_CLASS_MISMATCH')
    $observational = New-TestContext -Scenario 'HANG_IGNORE' -ModePolicy 'PREVIEW_APPLY' -EngineClass 'OBSERVATIONAL' -TimeoutSeconds 1
    $observationalOperation = [guid]::NewGuid().ToString()
    $result = Invoke-SisqualEngineHost -ActionCode $observational.Action.ActionCode -EngineClass OBSERVATIONAL -PackageRoot $observational.Root -CatalogPath $observational.Catalog -CatalogSession $observational.CatalogSession -ManifestEntries $observational.Manifest -Mode PREVIEW -InstanceCode $observational.Scenario -LockKeys @('INSTANCE:' + [string]$observational.Scenario) -OperationId $observationalOperation -CancellationGraceSeconds 1
    Check 'an engine of an action that can apply is retained on timeout whatever class is declared (never killed by the host)' ($result.errorMessage -ceq 'TIMED_OUT_RUNNING') ([string]$result.errorMessage)
    [void](Stop-SisqualTimedOutEngineProcess -OperationId $observationalOperation -Confirm:$false)
    $otherExe = if ($IsWindows) { Join-Path ([Environment]::SystemDirectory) 'cmd.exe' } else { '/bin/sh' }
    $pinned = New-TestContext
    Check 'the child executable must be the PowerShell this host runs in' (Throws-Code { Invoke-SisqualEngineHost -ActionCode $pinned.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $pinned.Root -CatalogPath $pinned.Catalog -CatalogSession $pinned.CatalogSession -ManifestEntries $pinned.Manifest -InstanceCode $pinned.Scenario -PwshPath $otherExe } 'PWSH_PATH_NOT_ALLOWED')

    # AGENTS.md: the action and the engine come from the verified catalog session, not from the caller.
    $parameters = (Get-Command Invoke-SisqualEngineHost).Parameters
    Check 'the host no longer accepts engine or action rows from the caller' (-not $parameters.ContainsKey('Engine') -and -not $parameters.ContainsKey('Action') -and $parameters.ContainsKey('ActionCode'))
    $fromCatalog = New-TestContext
    Check 'an action code that is not in the verified catalog is rejected before launch' (Throws-Code { Invoke-SisqualEngineHost -ActionCode 'OTHER_ACTION' -EngineClass READ_ONLY -PackageRoot $fromCatalog.Root -CatalogPath $fromCatalog.Catalog -CatalogSession $fromCatalog.CatalogSession -ManifestEntries $fromCatalog.Manifest -InstanceCode $fromCatalog.Scenario } 'ACTION_NOT_FOUND')
    $noEngine = New-TestContext; $noEngine.Engine.EngineCode = 'OTHER_ENGINE'
    Check 'an action whose engine is not in the verified catalog is rejected before launch' (Throws-Code { Invoke-TestHost -Context $noEngine } 'ENGINE_NOT_FOUND')
    # The launcher runs before the engine and receives the whole request, so it is verified against the manifest like the engine.
    $launcherCtx = New-TestContext
    $badLauncher = @($launcherCtx.Manifest | ForEach-Object { if ($_.path -ceq 'runtime/Invoke-SisqualEngineLauncher.ps1') { [pscustomobject]@{ path = $_.path; sha256 = ('0' * 64) } } else { $_ } })
    $noLauncher = @($launcherCtx.Manifest | Where-Object { $_.path -cne 'runtime/Invoke-SisqualEngineLauncher.ps1' })
    Check 'a launcher that does not match its manifest entry is not run' (Throws-Code { Invoke-SisqualEngineHost -ActionCode $launcherCtx.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $launcherCtx.Root -CatalogPath $launcherCtx.Catalog -CatalogSession $launcherCtx.CatalogSession -ManifestEntries $badLauncher -InstanceCode $launcherCtx.Scenario } 'ENGINE_LAUNCHER_HASH_MISMATCH')
    Check 'a launcher with no manifest entry is not run' (Throws-Code { Invoke-SisqualEngineHost -ActionCode $launcherCtx.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $launcherCtx.Root -CatalogPath $launcherCtx.Catalog -CatalogSession $launcherCtx.CatalogSession -ManifestEntries $noLauncher -InstanceCode $launcherCtx.Scenario } 'ENGINE_MANIFEST_ENTRY_INVALID')

    # ADR-0008 item 3: the credential references an engine may receive come from the approved package contract, not from an argument.
    $secretParameters = (Get-Command Invoke-SisqualEngineHost).Parameters
    Check 'the host no longer accepts a list of declared secrets from the caller' (-not $secretParameters.ContainsKey('DeclaredSecretReferences'))
    $contractCtx = New-TestContext
    $goodContract = Get-ManifestWithSecretContract -Context $contractCtx -Declared @('TEST_SECRET')
    $tamperedContract = @($goodContract | ForEach-Object { if ($_.path -ceq 'contracts/engine-secret-references.json') { [pscustomobject]@{ path = $_.path; sha256 = ('0' * 64) } } else { $_ } })
    Check 'a secret contract that does not match its manifest entry is not trusted' (Throws-Code { Invoke-SisqualEngineHost -ActionCode $contractCtx.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $contractCtx.Root -CatalogPath $contractCtx.Catalog -CatalogSession $contractCtx.CatalogSession -ManifestEntries $tamperedContract -InstanceCode $contractCtx.Scenario -Secrets @{ TEST_SECRET = 'a' } } 'ENGINE_SECRET_CONTRACT_INVALID')
    Check 'supplying secrets without a contract entry in the manifest is refused' (Throws-Code { Invoke-SisqualEngineHost -ActionCode $contractCtx.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $contractCtx.Root -CatalogPath $contractCtx.Catalog -CatalogSession $contractCtx.CatalogSession -ManifestEntries $contractCtx.Manifest -InstanceCode $contractCtx.Scenario -Secrets @{ TEST_SECRET = 'a' } } 'ENGINE_MANIFEST_ENTRY_INVALID')
    Check 'an adapter cannot widen the contract: a secret that the contract does not list is refused' (Throws-Code { Invoke-TestHost -Context $contractCtx -Secrets @{ TEST_SECRET = 'a'; EXTRA_SECRET = 'b' } -Declared @('TEST_SECRET') } 'SECRET_NOT_DECLARED')
    # An action that does not run an engine is classified before any engine is looked up.
    $composite = New-TestContext; $composite.Action.ActionType = 'COMPOSITE'; $composite.Action.EngineCode = $null
    Check 'a composite action without an engine code is classified, not looked up as an engine' (Throws-Code { Invoke-TestHost -Context $composite } 'ACTION_TYPE_REQUIRES_ORCHESTRATOR')
    $sqlAction = New-TestContext; $sqlAction.Action.ActionType = 'SQL'; $sqlAction.Action.EngineCode = ''
    Check 'a SQL action without an engine code is refused as unsupported, not as an invalid session' (Throws-Code { Invoke-TestHost -Context $sqlAction } 'ACTION_TYPE_NOT_SUPPORTED')

    $timedMutable = New-TestContext -Scenario 'HANG_IGNORE' -ModePolicy 'PREVIEW_APPLY' -EngineClass 'MUTATING' -TimeoutSeconds 1
    $operationId = [guid]::NewGuid().ToString()
    $result = Invoke-SisqualEngineHost -ActionCode $timedMutable.Action.ActionCode -EngineClass MUTATING -PackageRoot $timedMutable.Root -CatalogPath $timedMutable.Catalog -CatalogSession $timedMutable.CatalogSession -ManifestEntries $timedMutable.Manifest -Mode PREVIEW -InstanceCode $timedMutable.Scenario -OperationId $operationId -CancellationGraceSeconds 1
    Check 'mutable timeout stays running and is not killed by host' ($result.errorMessage -ceq 'TIMED_OUT_RUNNING') ([string]$result.errorMessage)
    Check 'explicit operator action can terminate retained timed-out test process' (Stop-SisqualTimedOutEngineProcess -OperationId $operationId -Confirm:$false)
}
finally {
    foreach ($root in $script:TempRoots) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ("EngineHost tests: {0} passed / {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -ne 0) { exit 1 }
