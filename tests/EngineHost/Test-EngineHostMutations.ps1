#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
$env:SISQUAL_ENGINEHOST_TEST_LOG = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-log-' + [guid]::NewGuid().ToString('N') + '.jsonl')
function global:Write-SisqualRuntimeLog {
    param([string]$Level,[string]$EventCode,[string]$Message,[hashtable]$Properties)
    $entry = [ordered]@{ level = $Level; eventCode = $EventCode; message = $Message; properties = $Properties }
    Add-Content -LiteralPath $env:SISQUAL_ENGINEHOST_TEST_LOG -Value ($entry | ConvertTo-Json -Compress -Depth 10) -Encoding utf8
    return $env:SISQUAL_ENGINEHOST_TEST_LOG
}
$script:Passed = 0
$script:Failed = 0
$script:Roots = [Collections.Generic.List[string]]::new()

function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:Passed++; Write-Host ('PASS  ' + $Name) } else { $script:Failed++; Write-Host ('FAIL  ' + $Name) }
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
    return [pscustomobject]@{
        Root = $root; Catalog = $catalog; Scenario = $Scenario
        Engine = [pscustomobject]@{ EngineCode = 'FAKE_ENGINE'; EngineVersion = 'test-1.0'; SourceFileName = $leaf; IsEnabled = 1; MinimumPowerShell = '7.0'; RequiresAdministrator = 0 }
        Action = [pscustomobject]@{ ActionCode = 'FAKE_ACTION'; EngineCode = 'FAKE_ENGINE'; IsEnabled = 1; ActionType = 'ENGINE'; ModePolicy = $ModePolicy; RequiresInstanceSelection = 1; AllowAllInstances = 1; InstanceSelectionPolicy = 'ALL_ENABLED'; PassInstanceCode = 1; PassApply = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 1 } else { 0 }); ConfirmationText = $(if ($ModePolicy -eq 'PREVIEW_APPLY') { 'CONFIRM' } else { '' }); CommandTimeoutSeconds = 5 }
        Manifest = @(
            [pscustomobject]@{ path = ('engines/' + $leaf); sha256 = $hash },
            [pscustomobject]@{ path = 'catalog/catalog-TEST.db'; sha256 = (Get-FileHash -LiteralPath $catalog -Algorithm SHA256).Hash.ToLowerInvariant(); size = (Get-Item -LiteralPath $catalog).Length }
        )
    }
}
function Run {
    param([object]$Ctx, [hashtable]$Secrets = @{}, [string]$MachineName = $env:COMPUTERNAME, [string]$Mode = 'PREVIEW', [string]$PlanFingerprint = $null, [string]$Confirmation = $null, [string]$Class = 'READ_ONLY')
    Invoke-SisqualEngineHost -Engine $Ctx.Engine -Action $Ctx.Action -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogMachineName $MachineName -ManifestEntries $Ctx.Manifest -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Ctx.Scenario) -CancellationGraceSeconds 1
}

try {
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

    $ctx = New-Ctx; $ctx.Engine.MinimumPowerShell = '99.0'
    Check 'mutation: unsupported minimum PowerShell is rejected' (Throws-Code { Run $ctx } 'POWERSHELL_VERSION_UNAVAILABLE')

    $ctx = New-Ctx
    Check 'mutation: foreign catalog machine is rejected' (Throws-Code { Run $ctx -MachineName 'NOT-THIS-MACHINE' } 'CATALOG_MACHINE_MISMATCH')

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

    $canary = 'canary value/+with?encoding=1'
    foreach ($scenario in @('SECRET_BASE64','SECRET_URL','SECRET_URL_LOWERHEX')) {
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

    $ctx = New-Ctx; $ctx.Action.RequiresInstanceSelection = 1
    Check 'mutation: required instance cannot be omitted' (Throws-Code {
        Invoke-SisqualEngineHost -Engine $ctx.Engine -Action $ctx.Action -EngineClass READ_ONLY -PackageRoot $ctx.Root -CatalogPath $ctx.Catalog -CatalogMachineName $env:COMPUTERNAME -ManifestEntries $ctx.Manifest -Mode PREVIEW -InstanceCode $null
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
