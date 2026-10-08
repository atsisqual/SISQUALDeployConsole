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
        [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = Get-FileSha256 -Path $catalogPath; size = (Get-Item -LiteralPath $catalogPath).Length }
    )
    return [pscustomobject]@{
        Root = $root
        Catalog = $catalogPath
        Engine = $engine
        Action = $action
        Manifest = $manifest
        CatalogSession = (New-SisqualTestCatalogSession -CatalogPath $catalogPath -MachineName $env:COMPUTERNAME)
        Class = $EngineClass
        Scenario = $Scenario
    }
}

function Invoke-TestHost {
    param(
        [object]$Context,
        [string]$Mode = 'PREVIEW',
        [string]$PlanFingerprint = $null,
        [string]$ConfirmationText = $null,
        [hashtable]$Secrets = @{}
    )
    return Invoke-SisqualEngineHost -Engine $Context.Engine -Action $Context.Action -EngineClass $Context.Class -PackageRoot $Context.Root -CatalogPath $Context.Catalog -CatalogSession $Context.CatalogSession -ManifestEntries $Context.Manifest -Mode $Mode -InstanceCode $Context.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $ConfirmationText -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Context.Scenario) -CancellationGraceSeconds 2
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
    $foreignMachine.CatalogSession | Add-Member -NotePropertyName MachineName -NotePropertyValue $env:COMPUTERNAME -Force
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
    $env:SISQUAL_FAKE_ENGINE_DELAY_STDIN_MS = '6000'
    try {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-TestHost -Context $asyncInput -Secrets @{ BULK = ('Z' * 262144) }
        $watch.Stop()
        Check 'large stdin cannot block timeout enforcement' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 5) ([string]$result.errorMessage)
    }
    finally { Remove-Item Env:\SISQUAL_FAKE_ENGINE_DELAY_STDIN_MS -ErrorAction SilentlyContinue }

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

    $timedMutable = New-TestContext -Scenario 'HANG_IGNORE' -ModePolicy 'PREVIEW_APPLY' -EngineClass 'MUTATING' -TimeoutSeconds 1
    $operationId = [guid]::NewGuid().ToString()
    $result = Invoke-SisqualEngineHost -Engine $timedMutable.Engine -Action $timedMutable.Action -EngineClass MUTATING -PackageRoot $timedMutable.Root -CatalogPath $timedMutable.Catalog -CatalogSession $timedMutable.CatalogSession -ManifestEntries $timedMutable.Manifest -Mode PREVIEW -InstanceCode $timedMutable.Scenario -OperationId $operationId -CancellationGraceSeconds 1
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
