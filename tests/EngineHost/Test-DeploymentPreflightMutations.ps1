#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$sourcePath = Join-Path $repo 'engines\Invoke-DeploymentPreflight.ps1'
$source = [IO.File]::ReadAllText($sourcePath)
$script:Passed = 0
$script:Failed = 0
function Check([string]$Name,[bool]$Condition) {
    if ($Condition) { $script:Passed++; Write-Host ('PASS  ' + $Name) }
    else { $script:Failed++; Write-Host ('FAIL  ' + $Name) }
}
function Invoke-ProbeProcess([string]$ScriptPath,[object]$Request) {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = (Get-Process -Id $PID).Path
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$ScriptPath)) { [void]$info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        [void]$process.Start()
        $process.StandardInput.Write(($Request | ConvertTo-Json -Compress -Depth 30))
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Stdout=$stdout; Stderr=$stderr }
    }
    finally { $process.Dispose() }
}

$reviewNames = @(
    'MANAGEMENT_MODEL','APPLICATION_CATALOG','MANAGED_ASSETS','REPAIR_MODEL','IIS_MODEL','EXTENDED_APPLICATIONS',
    'WINDOWS_SERVICES','WEB_ACCESS','LINKS_MODEL','LINKS_PRESENTATION','PULSE_MODEL','OPERATIONS_FRAMEWORK'
)
function Test-SourceContract([string]$Text) {
    if ($Text -notmatch "-cne 'PREVIEW'\) \{ Exit-InvalidRequest \}") { return $false }
    if ($Text -match '(?i)Invoke-Expression|ScriptBlock\]::Create') { return $false }
    if ($Text -match '(?is)ops_ReviewDefinition.{0,240}CommandText|CommandText.{0,240}ops_ReviewDefinition') { return $false }
    if ($Text -notmatch "IIS_IDENTITY_PASSWORD_PENDING") { return $false }
    if ($Text -notmatch "SERVICE_ACCOUNT_PASSWORD_MISSING") { return $false }
    if ($Text -notmatch "CATALOG_BUILT_AT") { return $false }
    if ($Text -notmatch "PRAGMA query_only=ON") { return $false }
    $tableLookupNeedle = "sqlite_master WHERE type=''table'' AND name=`$name"
    if (-not $Text.Contains($tableLookupNeedle,[StringComparison]::Ordinal)) { return $false }
    foreach ($review in $reviewNames) {
        $needle = $review + ' = ${function:'
        if (-not $Text.Contains($needle,[StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

Check 'unmodified preflight source satisfies the local contract anchors' (Test-SourceContract $source)
Check 'all 12 local reviews are registered exactly once' (@($reviewNames | Where-Object { ([regex]::Matches($source,[regex]::Escape($_ + ' = ${function:'))).Count -eq 1 }).Count -eq 12)
Check 'catalog review CommandText is never read as executable code' ($source -notmatch '(?is)ops_ReviewDefinition.{0,240}CommandText|CommandText.{0,240}ops_ReviewDefinition')

$hostStyleOperationId = [guid]::NewGuid().ToString()
Check 'host-style operation id matches the engine request envelope' ($hostStyleOperationId -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
Check 'fully-qualified existing Windows path passes the engine path gate' ([IO.Path]::IsPathFullyQualified($sourcePath) -and (Test-Path -LiteralPath $sourcePath -PathType Leaf))
$deadlineText = [DateTime]::UtcNow.AddMinutes(15).ToString('yyyy-MM-ddTHH:mm:ssZ')
$parsedDeadline = [datetime]::MinValue
$deadlineOk = [datetime]::TryParseExact($deadlineText,'yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,[ref]$parsedDeadline)
Check 'host-style deadline passes the engine exact UTC parser' $deadlineOk

$mutatedMode = $source.Replace("if ([string](Get-Field `$script:Request 'mode' '') -cne 'PREVIEW') { Exit-InvalidRequest }",'# mutation: READ_ONLY mode guard removed')
Check 'MUTATION remove READ_ONLY PREVIEW guard is detected' (-not (Test-SourceContract $mutatedMode))

$mutatedCredential = $source.Replace('IIS_IDENTITY_PASSWORD_PENDING','IIS_IDENTITY_PASSWORD_IGNORED')
Check 'MUTATION remove missing-IIS-credential error is detected' (-not (Test-SourceContract $mutatedCredential))

$mutatedReview = $source.Replace('PULSE_MODEL = ${function:Invoke-ReviewPulseModel}','PULSE_MODEL_DISABLED = ${function:Invoke-ReviewPulseModel}')
Check 'MUTATION remove one of the 12 review registrations is detected' (-not (Test-SourceContract $mutatedReview))

$mutatedCatalogAge = $source.Replace('CATALOG_BUILT_AT','CATALOG_AGE_SUPPRESSED')
Check 'MUTATION suppress catalog build-time INFO is detected' (-not (Test-SourceContract $mutatedCatalogAge))

$mutatedSql = $source + "`nInvoke-Expression 'SELECT 1'"
Check 'MUTATION introduce executable text primitive is detected' (-not (Test-SourceContract $mutatedSql))

$mutatedCatalogCommandText = $source + "`n`$rows = Get-CatalogRows 'ops_ReviewDefinition'; `$unsafe = `$rows[0].CommandText"
Check 'MUTATION read catalog review CommandText is detected' (-not (Test-SourceContract $mutatedCatalogCommandText))

# Instrument a temporary copy only: each invalid-request gate gets a distinct exit code.
# A valid request should pass all of them and reach the later package/catalog failure path instead.
$instrumented = $source
$gateReplacements = [ordered]@{
    "if ([string]::IsNullOrWhiteSpace(`$raw) -or [Text.UTF8Encoding]::new(`$false).GetByteCount(`$raw) -gt 1MB) { Exit-InvalidRequest }" = "if ([string]::IsNullOrWhiteSpace(`$raw) -or [Text.UTF8Encoding]::new(`$false).GetByteCount(`$raw) -gt 1MB) { exit 21 }"
    "if (`$null -eq `$script:Request.PSObject.Properties[`$name]) { Exit-InvalidRequest }" = "if (`$null -eq `$script:Request.PSObject.Properties[`$name]) { exit 22 }"
    "if ([string](Get-Field `$script:Request 'contractVersion' '') -cne `$script:ContractVersion) { Exit-InvalidRequest }" = "if ([string](Get-Field `$script:Request 'contractVersion' '') -cne `$script:ContractVersion) { exit 23 }"
    "if ([string](Get-Field `$script:Request 'engineCode' '') -cne `$script:EngineCode) { Exit-InvalidRequest }" = "if ([string](Get-Field `$script:Request 'engineCode' '') -cne `$script:EngineCode) { exit 24 }"
    "if ([string](Get-Field `$script:Request 'mode' '') -cne 'PREVIEW') { Exit-InvalidRequest }" = "if ([string](Get-Field `$script:Request 'mode' '') -cne 'PREVIEW') { exit 25 }"
    "if ([string](Get-Field `$script:Request 'operationId' '') -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { Exit-InvalidRequest }" = "if ([string](Get-Field `$script:Request 'operationId' '') -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { exit 26 }"
    "if (-not [IO.Path]::IsPathFullyQualified(`$catalogPath) -or -not (Test-Path -LiteralPath `$catalogPath -PathType Leaf) -or [string]::IsNullOrWhiteSpace(`$resultPath)) { Exit-InvalidRequest }" = "if (-not [IO.Path]::IsPathFullyQualified(`$catalogPath) -or -not (Test-Path -LiteralPath `$catalogPath -PathType Leaf) -or [string]::IsNullOrWhiteSpace(`$resultPath)) { exit 27 }"
    "if (-not [datetime]::TryParseExact([string](Get-Field `$script:Request 'deadlineUtc' ''),'yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,[ref]`$deadline)) { Exit-InvalidRequest }" = "if (-not [datetime]::TryParseExact([string](Get-Field `$script:Request 'deadlineUtc' ''),'yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,[ref]`$deadline)) { exit 28 }"
    "catch { Exit-InvalidRequest }" = "catch { exit 29 }"
}
foreach ($replacement in $gateReplacements.GetEnumerator()) {
    Check ('diagnostic gate source exists before instrumentation: ' + $replacement.Value.Substring($replacement.Value.LastIndexOf('exit '))) ($instrumented.Contains([string]$replacement.Key,[StringComparison]::Ordinal))
    $instrumented = $instrumented.Replace([string]$replacement.Key,[string]$replacement.Value)
}
$probeRoot = Join-Path $env:TEMP ('sisqual-preflight-gate-probe-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $probeRoot 'engines') -Force | Out-Null
    $probeScript = Join-Path $probeRoot 'engines\Invoke-DeploymentPreflight.ps1'
    [IO.File]::WriteAllText($probeScript,$instrumented,[Text.UTF8Encoding]::new($false))
    $probeRequest = [ordered]@{
        contractVersion='0.1-proposed'; operationId='00000000-0000-4000-8000-000000000401'; engineCode='DEPLOYMENT_PREFLIGHT'; mode='PREVIEW'; instanceCode='INST1'
        catalogPath=$sourcePath; planFingerprint=$null; deadlineUtc=$deadlineText; cancelPath=(Join-Path $probeRoot 'cancel'); resultPath=(Join-Path $probeRoot 'result.json'); secrets=@{}
    }
    $probe = Invoke-ProbeProcess -ScriptPath $probeScript -Request $probeRequest
    $gateNames = @{ 21='raw-size';22='required-property';23='contract-version';24='engine-code';25='mode';26='operation-id';27='catalog-or-result-path';28='deadline';29='unexpected-validation-exception' }
    if ($gateNames.ContainsKey([int]$probe.ExitCode)) { Write-Host ('DIAG  instrumented-envelope: gate={0}; exitCode={1}' -f $gateNames[[int]$probe.ExitCode],$probe.ExitCode) }
    Check 'instrumented valid envelope passes every invalid-request gate' (-not $gateNames.ContainsKey([int]$probe.ExitCode) -and $probe.ExitCode -ne 2)
}
finally { Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ("SUMMARY: {0} passed, {1} failed" -f $script:Passed,$script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0