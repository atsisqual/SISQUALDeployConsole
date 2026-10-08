#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
. (Join-Path $PSScriptRoot 'TestCatalogSessionStub.ps1')
Initialize-SisqualEngineHostCatalogStub
$env:SISQUAL_ENGINEHOST_TEST_LOG = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-log-' + [guid]::NewGuid().ToString('N') + '.jsonl')
function global:Write-SisqualRuntimeLog {
    param([string]$Level,[string]$EventCode,[string]$Message,[hashtable]$Properties)
    $entry = [ordered]@{ level = $Level; eventCode = $EventCode; message = $Message; properties = $Properties }
    Add-Content -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding utf8
    return $env:SISQUAL_ENGINEHOST_TEST_LOG
}
$script:LauncherHash = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '..' '..' 'runtime' 'Invoke-SisqualEngineLauncher.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
$script:Passed = 0
$script:Failed = 0
$script:Roots = [Collections.Generic.List[string]]::new()

function Show-HostLogTail {
    if ($env:SISQUAL_ENGINEHOST_TEST_LOG -and (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG)) {
        foreach ($line in @(Get-Content -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Tail 3)) { Write-Host ('      host log: ' + $line) }
    }
}
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:Passed++; Write-Host ('PASS  ' + $Name) } else { $script:Failed++; Write-Host ('FAIL  ' + $Name); Show-HostLogTail }
}
function Throws-Code([scriptblock]$Script, [string]$Code) {
    try { & $Script | Out-Null; return $false } catch { return $_.Exception.Message -ceq $Code }
}
function New-Ctx([string]$Scenario = 'GOOD', [string]$ModePolicy = 'NONE') {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-mutation-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'engines')); $script:Roots.Add($root)
    $leaf = 'FakeEngine.ps1'; $path = Join-Path (Join-Path $root 'engines') $leaf
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'FakeEngine.ps1') -Destination $path
    $catalogDir = Join-Path $root 'catalog'; [void][IO.Directory]::CreateDirectory($catalogDir)
    $catalog = Join-Path $catalogDir 'catalog-TEST.db'; Set-Content -LiteralPath $catalog -Value 'synthetic' -NoNewline -Encoding ascii
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $built = [pscustomobject]@{
        Root = $root; Catalog = $catalog; Scenario = $Scenario; CatalogSession = (New-SisqualTestCatalogSession -CatalogPath $catalog -MachineName ([Environment]::MachineName))
        Engine = [pscustomobject]@{ EngineCode = 'FAKE_ENGINE'; EngineVersion = 'test-1.0'; SourceFileName = $leaf; IsEnabled = 1; MinimumPowerShell = '7.0'; RequiresAdministrator = 0 }
        Action = [pscustomobject]@{ ActionCode = 'FAKE_ACTION'; EngineCode = 'FAKE_ENGINE'; IsEnabled = 1; ActionType = 'ENGINE'; ModePolicy = $ModePolicy; RequiresInstanceSelection = 1; AllowAllInstances = 1; InstanceSelectionPolicy = 'ALL_ENABLED'; PassInstanceCode = 1; PassApply = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 1 } else { 0 }); ConfirmationText = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 'CONFIRM' } else { '' }); CommandTimeoutSeconds = 5 }
        Manifest = @(
            [pscustomobject]@{ path = ('engines/' + $leaf); sha256 = $hash },
            [pscustomobject]@{ path = 'runtime/Invoke-SisqualEngineLauncher.ps1'; sha256 = $script:LauncherHash },
            [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant(); size = (Get-Item -LiteralPath $catalog).Length }
        )
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
function Run {
    param([object]$Ctx, [hashtable]$Secrets = @{}, [string]$Mode = 'PREVIEW', [string]$PlanFingerprint = $null, [string]$Confirmation = $null, [string]$Class = 'READ_ONLY', [string[]]$Declared = $null)
    if ($null -eq $Declared) { $Declared = @($Secrets.Keys | ForEach-Object { [string]$_ }) }
    $manifestForCall = if ($Secrets.Count -gt 0) { Get-ManifestWithSecretContract -Context $Ctx -Declared $Declared } else { $Ctx.Manifest }
    Invoke-SisqualEngineHost -ActionCode $Ctx.Action.ActionCode -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogSession $Ctx.CatalogSession -ManifestEntries $manifestForCall -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Ctx.Scenario) -CancellationGraceSeconds 1
}

try {
    $ctx = New-Ctx; $ctx.Engine.IsEnabled = 0
    Check 'mutation: disabled engine is rejected' (Throws-Code { Run $ctx } 'ENGINE_DISABLED')

    $ctx = New-Ctx; $ctx.Action.IsEnabled = 0
    Check 'mutation: disabled action is rejected' (Throws-Code { Run $ctx } 'ACTION_DISABLED')

    $ctx = New-Ctx; $ctx.Action.EngineCode = 'OTHER_ENGINE'
    Check 'mutation: an action that names an engine that is not in the verified catalog is rejected (the engine is resolved from the action, so the mapping is exact by construction)' (Throws-Code { Run $ctx } 'ENGINE_NOT_FOUND')

    $ctx = New-Ctx; $rogue = Join-Path $ctx.Root 'other.db'; Set-Content -LiteralPath $rogue -Value 'synthetic' -NoNewline -Encoding ascii; $ctx.Catalog = $rogue
    Check 'mutation: arbitrary catalog path is rejected' (Throws-Code { Run $ctx } 'CATALOG_PATH_MISMATCH')

    $ctx = New-Ctx; Add-Content -LiteralPath $ctx.Catalog -Value 'tamper' -NoNewline -Encoding ascii
    Check 'mutation: catalog hash is reverified before launch' (Throws-Code { Run $ctx } 'CATALOG_HASH_MISMATCH')

    $ctx = New-Ctx; $ctx.Engine.MinimumPowerShell = '99.0'
    Check 'mutation: unsupported minimum PowerShell is rejected' (Throws-Code { Run $ctx } 'POWERSHELL_VERSION_UNAVAILABLE')

    $ctx = New-Ctx
    Set-SisqualTestCatalogMachineName -Session $ctx.CatalogSession -MachineName 'NOT-THIS-MACHINE'
    $ctx.CatalogSession | Add-Member -NotePropertyName MachineName -NotePropertyValue ([Environment]::MachineName) -Force
    Check 'mutation: foreign catalog machine is rejected from authenticated session metadata' (Throws-Code { Run $ctx } 'CATALOG_MACHINE_MISMATCH')

    $ctx = New-Ctx
    $ctx.CatalogSession = [pscustomobject]@{ SessionId = [guid]::NewGuid().ToString('N'); CatalogPath = $ctx.Catalog }
    Check 'mutation: forged catalog session is rejected' (Throws-Code { Run $ctx } 'CATALOG_SESSION_INVALID')

    $ctx = New-Ctx; $ctx.Engine.SourceFileName = '..\FakeEngine.ps1'
    Check 'mutation: path traversal SourceFileName is rejected' (Throws-Code { Run $ctx } 'ENGINE_SOURCE_FILENAME_INVALID')

    $ctx = New-Ctx; $ctx.Manifest[0].sha256 = ('0' * 64)
    Check 'mutation: tampered engine hash is rejected' (Throws-Code { Run $ctx } 'ENGINE_HASH_MISMATCH')

    $ctx = New-Ctx; $ctx.Manifest += [pscustomobject]@{ path = 'engines/FakeEngine.ps1'; sha256 = $ctx.Manifest[0].sha256 }
    Check 'mutation: duplicate manifest engine entry is rejected' (Throws-Code { Run $ctx } 'ENGINE_MANIFEST_ENTRY_INVALID')

    foreach ($scenario in @('INVALID_SHAPE','INVALID_BACKUP','INVALID_BACKUP_TYPES','INVALID_TOP_STRING_TYPES','INVALID_ROW_STRING_TYPES')) {
        $ctx = New-Ctx -Scenario $scenario; $result = Run $ctx
        Check ("mutation: malformed result rejected ({0})" -f $scenario) ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')
    }

    if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { Remove-Item -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Force }
    $ctx = New-Ctx -Scenario 'NO_RESULT'; $result = Run $ctx
    Check 'mutation: successful exit without result becomes ENGINE_NO_RESULT' ($result.errorMessage -ceq 'ENGINE_NO_RESULT')
    $failureLog = if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { [IO.File]::ReadAllText($env:SISQUAL_ENGINEHOST_TEST_LOG) } else { '' }
    Check 'mutation: failed completion is audit logged' ($failureLog.Contains('ENGINE.FAIL',[StringComparison]::Ordinal) -and $failureLog.Contains('operationId',[StringComparison]::Ordinal) -and $failureLog.Contains('ENGINE_NO_RESULT',[StringComparison]::Ordinal) -and $failureLog.Contains('planFingerprint',[StringComparison]::Ordinal) -and $failureLog.Contains('locks',[StringComparison]::Ordinal) -and $failureLog.Contains('targetCount',[StringComparison]::Ordinal))

    if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { Remove-Item -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Force }
    $ctx = New-Ctx; $result = Run $ctx
    $completionLog = if (Test-Path -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG) { [IO.File]::ReadAllText($env:SISQUAL_ENGINEHOST_TEST_LOG) } else { '' }
    Check 'mutation: completion audit carries plan locks and summary' ($completionLog.Contains('planFingerprint',[StringComparison]::Ordinal) -and $completionLog.Contains('locks',[StringComparison]::Ordinal) -and $completionLog.Contains('targetCount',[StringComparison]::Ordinal) -and $completionLog.Contains('failedTargets',[StringComparison]::Ordinal) -and $completionLog.Contains('errorCount',[StringComparison]::Ordinal))

    $ctx = New-Ctx -Scenario 'UNEXPECTED_EXIT'; $result = Run $ctx
    Check 'mutation: undocumented process exit code becomes ENGINE_NO_RESULT' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and -not $result.succeeded)

    $ctx = New-Ctx -Scenario 'STREAM_LIMIT'; $result = Run $ctx
    Check 'mutation: stdout above 1 MiB is bounded' ($result.errorMessage -ceq 'ENGINE_STREAM_LIMIT')

    $ctx = New-Ctx -Scenario 'DESCENDANT_PIPE'; $ctx.Action.CommandTimeoutSeconds = 2
    $watch = [Diagnostics.Stopwatch]::StartNew(); $result = Run $ctx; $watch.Stop()
    Check 'mutation: inherited descendant pipe cannot block redirected stream drain' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 6)

    $ctx = New-Ctx -Scenario 'INVALID_UTF8_RESULT'; $result = Run $ctx
    Check 'mutation: invalid UTF-8 result becomes ENGINE_INVALID_RESULT' ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')

    # The launcher gate: a helper started during the engine's own initialisation is inside the job object as well.
    if ($IsWindows) {
        $ctx = New-Ctx
        $earlyMarker = [guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText((Join-Path (Join-Path $ctx.Root 'engines') 'early-helper.flag'), $earlyMarker)
        $result = Run $ctx
        $earlyAlive = $true
        for ($i = 0; $i -lt 20 -and $earlyAlive; $i++) {
            $earlyAlive = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($earlyMarker) }).Count -gt 0
            if ($earlyAlive) { Start-Sleep -Milliseconds 250 }
        }
        Check 'mutation: a helper started during engine initialisation is inside the job (launcher gate) and is terminated' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and -not $earlyAlive)
    }
    # Containment: everything the engine starts lives in a job object, so an orphaned grandchild is reached without any process id logic.
    if ($IsWindows) {
        $ctx = New-Ctx -Scenario 'GRANDCHILD'; $result = Run $ctx
        $marker = [string]$result.operationId
        $alive = $true
        for ($i = 0; $i -lt 20 -and $alive; $i++) {
            $alive = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($marker) }).Count -gt 0
            if ($alive) { Start-Sleep -Milliseconds 250 }
        }
        Check 'mutation: an orphaned grandchild is terminated through the job and the run is ENGINE_NO_RESULT' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and -not $alive)
    }

    # A failed containment must not leave the gated launcher alive.
    $module = Get-Module Sisqual.Runtime.EngineHost
    $originalContainment = & $module { (Get-Item Function:New-SisqualEngineContainment).ScriptBlock }
    & $module { Set-Item -Path Function:New-SisqualEngineContainment -Value { throw 'simulated containment failure' } }
    try {
        $ctx = New-Ctx
        Check 'mutation: a failed containment is ENGINE_CONTAINMENT_FAILED' (Throws-Code { Run $ctx } 'ENGINE_CONTAINMENT_FAILED')
        if ($IsWindows) {
            Start-Sleep -Milliseconds 500
            $leftover = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains([string]$ctx.Root) }).Count
            Check 'mutation: a failed containment leaves no launcher process waiting for its gate' ($leftover -eq 0)
        }
    }
    finally { & $module { param($block) Set-Item -Path Function:New-SisqualEngineContainment -Value $block } $originalContainment }

    $ctx = New-Ctx -Scenario 'STREAM_FLOOD'
    $watch = [Diagnostics.Stopwatch]::StartNew(); $result = Run $ctx; $watch.Stop()
    Check 'mutation: an engine that floods past the limit gets ENGINE_STREAM_LIMIT at once, not after the timeout' ($result.errorMessage -ceq 'ENGINE_STREAM_LIMIT' -and $watch.Elapsed.TotalSeconds -lt 4) (('{0} after {1:n1} s' -f $result.errorMessage, $watch.Elapsed.TotalSeconds))
    $ctx = New-Ctx -Scenario 'RESULT_ROOT_ARRAY'; $result = Run $ctx
    Check 'mutation: a valid result wrapped in a root array is ENGINE_INVALID_RESULT' ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')
    $canary = 'canary value/+with?encoding=1'
    foreach ($scenario in @('SECRET_BASE64','SECRET_URL','SECRET_URL_LOWERHEX','SECRET_URL_FORM')) {
        $ctx = New-Ctx -Scenario $scenario; $result = Run $ctx -Secrets @{ TEST_SECRET = $canary }
        Check ("mutation: encoded secret detected ({0})" -f $scenario) ($result.errorMessage -ceq 'SECRET_LEAK')
    }

    $ctx = New-Ctx -Scenario 'SECRET_RESULT_ALT_ESCAPE'; $result = Run $ctx -Secrets @{ TEST_SECRET = 'pass' }
    Check 'mutation: decoded alternate Unicode escape secret in result is detected' ($result.errorMessage -ceq 'SECRET_LEAK')

    $jsonCanary = 'p"ass\word'
    $ctx = New-Ctx -Scenario 'SECRET_RESULT'; $result = Run $ctx -Secrets @{ TEST_SECRET = $jsonCanary }
    Check 'mutation: JSON-escaped secret in result is detected' ($result.errorMessage -ceq 'SECRET_LEAK')

    $ctx = New-Ctx -ModePolicy 'PREVIEW_APPLY'; $preview = Run $ctx -Class MUTATING
    Check 'mutation setup: successful preview fingerprint exists' ([string]$preview.planFingerprint -match '^[0-9a-f]{64}$')
    Check 'mutation: APPLY requires exact confirmation text' (Throws-Code { Run $ctx -Class MUTATING -Mode APPLY -PlanFingerprint ([string]$preview.planFingerprint) -Confirmation 'WRONG' } 'CONFIRMATION_REQUIRED')

    $failedPreview = New-Ctx -Scenario 'FAILED_PREVIEW' -ModePolicy 'PREVIEW_APPLY'; $preview = Run $failedPreview -Class MUTATING
    Check 'mutation setup: failed preview carries fingerprint but remains failed' (-not $preview.succeeded -and [string]$preview.planFingerprint -match '^[0-9a-f]{64}$')
    Check 'mutation: failed preview fingerprint is not cached for APPLY' (Throws-Code { Run $failedPreview -Class MUTATING -Mode APPLY -PlanFingerprint ([string]$preview.planFingerprint) -Confirmation 'CONFIRM' } 'PLAN_CHANGED')

    $ctx = New-Ctx; $ctx.Action.RequiresInstanceSelection = 1; $ctx.Action.AllowAllInstances = 0
    Check 'mutation: required instance cannot be omitted' (Throws-Code {
        Invoke-SisqualEngineHost -ActionCode $ctx.Action.ActionCode -EngineClass READ_ONLY -PackageRoot $ctx.Root -CatalogPath $ctx.Catalog -CatalogSession $ctx.CatalogSession -ManifestEntries $ctx.Manifest -Mode PREVIEW -InstanceCode $null
    } 'INSTANCE_REQUIRED')
}
finally {
    foreach ($root in $script:Roots) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Force -ErrorAction SilentlyContinue
    Remove-Item Function:\Write-SisqualRuntimeLog -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\SISQUAL_ENGINEHOST_TEST_LOG -ErrorAction SilentlyContinue
}

Write-Host ("EngineHost mutation matrix: {0} passed / {1} failed" -f $script:Passed, $script:Failed)
if ($script:Failed -ne 0) { exit 1 }
