#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1'
$text = [IO.File]::ReadAllText($modulePath)

$mutations = @(
    [pscustomobject]@{
        Name = 'disable manifest hash enforcement'
        Find = "if (`$actualHash -cne `$expectedHash) { throw 'ENGINE_HASH_MISMATCH' }"
        Replace = "if (`$false) { throw 'ENGINE_HASH_MISMATCH' }"
        Evidence = 'ENGINE_HASH_MISMATCH'
    },
    [pscustomobject]@{
        Name = 'disable secret leak rejection'
        Find = "if (Find-SisqualSecretLeak -Texts `$rawScanTargets -Secrets `$Secrets) {"
        Replace = "if (`$false) {"
        Evidence = 'SECRET_LEAK'
    },
    [pscustomobject]@{
        Name = 'disable result arithmetic validation'
        Find = "if ((`$summarySucceeded + `$summaryFailed) -gt `$summaryTarget) { return `$false }"
        Replace = "if (`$false) { return `$false }"
        Evidence = 'ENGINE_INVALID_RESULT'
    },
    [pscustomobject]@{
        Name = 'allow APPLY without preview continuity'
        Find = "if (-not `$script:PreviewFingerprints.ContainsKey(`$previewKey) -or `$script:PreviewFingerprints[`$previewKey] -cne `$PlanFingerprint) { throw 'PLAN_CHANGED' }"
        Replace = "if (`$false) { throw 'PLAN_CHANGED' }"
        Evidence = 'PLAN_CHANGED'
    }
)

$passed = 0
$failed = 0
foreach ($mutation in $mutations) {
    $count = ([regex]::Matches($text, [regex]::Escape($mutation.Find))).Count
    if ($count -eq 1) {
        $mutated = $text.Replace($mutation.Find, $mutation.Replace)
        if ($mutated -cne $text -and $mutated.Contains($mutation.Replace, [StringComparison]::Ordinal)) {
            $passed++
            Write-Host ('PASS  mutation target is live: ' + $mutation.Name + ' -> ' + $mutation.Evidence)
        }
        else {
            $failed++
            Write-Host ('FAIL  mutation replacement did not change module: ' + $mutation.Name)
        }
    }
    else {
        $failed++
        Write-Host ('FAIL  mutation target count was not exactly one: ' + $mutation.Name + ' count=' + $count)
    }
}

Write-Host ("EngineHost source mutation anchors: {0} passed / {1} failed" -f $passed, $failed)
if ($failed -ne 0) { exit 1 }
