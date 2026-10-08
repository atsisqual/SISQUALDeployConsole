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

$reviewNames = @(
    'MANAGEMENT_MODEL','APPLICATION_CATALOG','MANAGED_ASSETS','REPAIR_MODEL','IIS_MODEL','EXTENDED_APPLICATIONS',
    'WINDOWS_SERVICES','WEB_ACCESS','LINKS_MODEL','LINKS_PRESENTATION','PULSE_MODEL','OPERATIONS_FRAMEWORK'
)
function Test-SourceContract([string]$Text) {
    if ($Text -notmatch "-cne 'PREVIEW'\) \{ Exit-InvalidRequest \}") { return $false }
    if ($Text -match '(?i)Invoke-Expression|ScriptBlock\]::Create|\.CommandText\b') { return $false }
    if ($Text -notmatch "IIS_IDENTITY_PASSWORD_PENDING") { return $false }
    if ($Text -notmatch "SERVICE_ACCOUNT_PASSWORD_MISSING") { return $false }
    if ($Text -notmatch "CATALOG_BUILT_AT") { return $false }
    if ($Text -notmatch "PRAGMA query_only=ON") { return $false }
    if ($Text -notmatch "sqlite_master WHERE type=''table'' AND name=\$name") { return $false }
    foreach ($review in $reviewNames) {
        $needle = $review + ' = ${function:'
        if (-not $Text.Contains($needle,[StringComparison]::Ordinal)) { return $false }
    }
    return $true
}

Check 'unmodified preflight source satisfies the local contract anchors' (Test-SourceContract $source)
Check 'all 12 local reviews are registered exactly once' (@($reviewNames | Where-Object { ([regex]::Matches($source,[regex]::Escape($_ + ' = ${function:'))).Count -eq 1 }).Count -eq 12)
Check 'catalog review CommandText is never read as executable code' ($source -notmatch '(?i)ops_ReviewDefinition.*CommandText|CommandText.*ops_ReviewDefinition')

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

Write-Host ("SUMMARY: {0} passed, {1} failed" -f $script:Passed,$script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
