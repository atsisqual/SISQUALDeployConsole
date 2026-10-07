#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force

$passed = 0
$failed = 0

function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:passed++; Write-Host ('PASS  ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL  ' + $Name) }
}

$planA = [ordered]@{ z = 1; a = [ordered]@{ y = 2; b = 3 } }
$planB = [ordered]@{ a = [ordered]@{ b = 3; y = 2 }; z = 1 }
$fingerprintA = Get-SisqualPlanFingerprint -Plan $planA
$fingerprintB = Get-SisqualPlanFingerprint -Plan $planB
Check 'canonical plan fingerprint ignores map insertion order' ($fingerprintA -ceq $fingerprintB)

$children = @(
    [pscustomobject]@{ step = 30; engineCode = 'C_ENGINE'; instanceCode = 'C'; planFingerprint = ('c' * 64) },
    [pscustomobject]@{ step = 10; engineCode = 'A_ENGINE'; instanceCode = 'A'; planFingerprint = ('a' * 64) },
    [pscustomobject]@{ step = 20; engineCode = 'B_ENGINE'; instanceCode = 'B'; planFingerprint = ('b' * 64) }
)
$aggregate = Get-SisqualCompositePlanFingerprint -Children $children
$reordered = Get-SisqualCompositePlanFingerprint -Children @($children[1], $children[2], $children[0])
Check 'aggregate fingerprint is deterministic by ordered child identity' ($aggregate -ceq $reordered)

Write-Host ("EngineHost fingerprint tests: {0} passed / {1} failed" -f $passed, $failed)
if ($failed -ne 0) { exit 1 }
