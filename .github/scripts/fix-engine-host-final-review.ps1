#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Replace-ExactlyOnce {
    param([string]$Path,[string]$Old,[string]$New)
    $text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
    $first = $text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($first -lt 0) { throw "Expected patch anchor not found in $Path" }
    if ($text.IndexOf($Old, $first + $Old.Length, [StringComparison]::Ordinal) -ge 0) { throw "Patch anchor is not unique in $Path" }
    $updated = $text.Substring(0,$first) + $New + $text.Substring($first + $Old.Length)
    [IO.File]::WriteAllText((Resolve-Path -LiteralPath $Path), $updated, [Text.UTF8Encoding]::new($false))
}

$hostPath = 'runtime/Sisqual.Runtime.EngineHost.psm1'
$fakePath = 'tests/EngineHost/FakeEngine.ps1'
$mutationPath = 'tests/EngineHost/Test-EngineHostMutations.ps1'

$old = @'
function Find-SisqualSecretLeak {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Texts, [System.Collections.IDictionary]$Secrets)
    foreach ($representation in (Get-SisqualSecretRepresentations $Secrets)) {
        foreach ($text in $Texts) {
            if ($null -ne $text -and $text.Contains($representation, [StringComparison]::Ordinal)) { return $true }
        }
    }
    return $false
}
'@
$new = @'
function Find-SisqualSecretLeak {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Texts, [System.Collections.IDictionary]$Secrets)
    $representations = Get-SisqualSecretRepresentations $Secrets
    foreach ($text in $Texts) {
        if ($null -eq $text) { continue }
        foreach ($representation in $representations) {
            if ($text.Contains($representation, [StringComparison]::Ordinal)) { return $true }
        }

        # URI percent escapes are case-insensitive for their hexadecimal digits. Decode the
        # complete text once before comparison so equivalent forms such as %2F and %2f cannot
        # bypass the secret scan while preserving ordinal comparison for the secret itself.
        $decodedText = $text
        try { $decodedText = [Uri]::UnescapeDataString($text) } catch { $decodedText = $text }
        if (-not $decodedText.Equals($text, [StringComparison]::Ordinal)) {
            foreach ($representation in $representations) {
                if ($decodedText.Contains($representation, [StringComparison]::Ordinal)) { return $true }
            }
        }
    }
    return $false
}
'@
Replace-ExactlyOnce $hostPath $old $new

$old = @'
    foreach ($name in $required) { if ($null -eq $Result.PSObject.Properties[$name]) { return $false } }
    foreach ($property in $Result.PSObject.Properties) { if ($allowed -cnotcontains $property.Name) { return $false } }
    if ([string]$Result.contractVersion -cne $script:EngineHostContractVersion -or [string]$Result.operationId -cne $OperationId -or [string]$Result.engineCode -cne $EngineCode -or [string]$Result.mode -cne $Mode) { return $false }
'@
$new = @'
    foreach ($name in $required) { if ($null -eq $Result.PSObject.Properties[$name]) { return $false } }
    foreach ($property in $Result.PSObject.Properties) { if ($allowed -cnotcontains $property.Name) { return $false } }
    foreach ($name in @('contractVersion','operationId','engineCode','engineVersion','mode','startedAt','completedAt')) {
        if ($Result.$name -isnot [string]) { return $false }
    }
    if ([string]$Result.contractVersion -cne $script:EngineHostContractVersion -or [string]$Result.operationId -cne $OperationId -or [string]$Result.engineCode -cne $EngineCode -or [string]$Result.mode -cne $Mode) { return $false }
'@
Replace-ExactlyOnce $hostPath $old $new

$old = @'
    if ($null -ne $Result.PSObject.Properties['planFingerprint'] -and [string]$Result.planFingerprint -notmatch '^[0-9a-f]{64}$') { return $false }
    if ($null -ne $Result.PSObject.Properties['errorMessage'] -and ([string]$Result.errorMessage).Length -gt 2000) { return $false }
'@
$new = @'
    if ($null -ne $Result.PSObject.Properties['planFingerprint'] -and ($Result.planFingerprint -isnot [string] -or $Result.planFingerprint -notmatch '^[0-9a-f]{64}$')) { return $false }
    if ($null -ne $Result.PSObject.Properties['errorMessage'] -and ($Result.errorMessage -isnot [string] -or $Result.errorMessage.Length -gt 2000)) { return $false }
'@
Replace-ExactlyOnce $hostPath $old $new

$old = @'
        foreach ($name in $rowRequired) { if ($null -eq $row.PSObject.Properties[$name]) { return $false } }
        foreach ($property in $row.PSObject.Properties) { if ($rowAllowed -cnotcontains $property.Name) { return $false } }
        if ([string]$row.timestamp -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { return $false }
        if (([string]$row.instanceCode).Length -gt 60 -or ([string]$row.object).Length -gt 400) { return $false }
        if ([string]$row.operationType -notmatch '^[A-Z][A-Z0-9_]{1,59}$' -or [string]$row.status -notmatch '^[A-Za-z][A-Za-z0-9_]{1,59}$') { return $false }
        if ($null -ne $row.PSObject.Properties['details'] -and ([string]$row.details).Length -gt 2000) { return $false }
'@
$new = @'
        foreach ($name in $rowRequired) { if ($null -eq $row.PSObject.Properties[$name]) { return $false } }
        foreach ($property in $row.PSObject.Properties) { if ($rowAllowed -cnotcontains $property.Name) { return $false } }
        foreach ($name in @('timestamp','instanceCode','operationType','object','status')) {
            if ($row.$name -isnot [string]) { return $false }
        }
        if ([string]$row.timestamp -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { return $false }
        if (([string]$row.instanceCode).Length -gt 60 -or ([string]$row.object).Length -gt 400) { return $false }
        if ([string]$row.operationType -notmatch '^[A-Z][A-Z0-9_]{1,59}$' -or [string]$row.status -notmatch '^[A-Za-z][A-Za-z0-9_]{1,59}$') { return $false }
        if ($null -ne $row.PSObject.Properties['details'] -and ($row.details -isnot [string] -or $row.details.Length -gt 2000)) { return $false }
'@
Replace-ExactlyOnce $hostPath $old $new

$old = @'
    'SECRET_URL' {
        [Console]::Error.WriteLine([Uri]::EscapeDataString($secretValue))
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_RESULT_ALT_ESCAPE' {
'@
$new = @'
    'SECRET_URL' {
        [Console]::Error.WriteLine([Uri]::EscapeDataString($secretValue))
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_URL_LOWERHEX' {
        $encoded = [Uri]::EscapeDataString($secretValue)
        $encoded = [regex]::Replace($encoded, '%[0-9A-F]{2}', { param($match) $match.Value.ToLowerInvariant() })
        [Console]::Error.WriteLine($encoded)
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'SECRET_RESULT_ALT_ESCAPE' {
'@
Replace-ExactlyOnce $fakePath $old $new

$old = @'
    'INVALID_BACKUP_TYPES' {
        $result = New-Result -Request $request -Succeeded $true
        $result.backup = [ordered]@{ created = $true; name = 42; location = $true; restoreHint = @{} }
        Write-ResultFile $request $result
        exit 0
    }
    'INVALID_ARITHMETIC' {
'@
$new = @'
    'INVALID_BACKUP_TYPES' {
        $result = New-Result -Request $request -Succeeded $true
        $result.backup = [ordered]@{ created = $true; name = 42; location = $true; restoreHint = @{} }
        Write-ResultFile $request $result
        exit 0
    }
    'INVALID_TOP_STRING_TYPES' {
        $result = New-Result -Request $request -Succeeded $true
        $result.engineVersion = 42
        $result.errorMessage = 42
        $result.planFingerprint = 42
        Write-ResultFile $request $result
        exit 0
    }
    'INVALID_ROW_STRING_TYPES' {
        $result = New-Result -Request $request -Succeeded $true
        $result.results[0].timestamp = 42
        $result.results[0].object = 42
        $result.results[0].details = 42
        Write-ResultFile $request $result
        exit 0
    }
    'INVALID_ARITHMETIC' {
'@
Replace-ExactlyOnce $fakePath $old $new

$old = "    foreach (`$scenario in @('INVALID_SHAPE','INVALID_BACKUP','INVALID_BACKUP_TYPES')) {"
$new = "    foreach (`$scenario in @('INVALID_SHAPE','INVALID_BACKUP','INVALID_BACKUP_TYPES','INVALID_TOP_STRING_TYPES','INVALID_ROW_STRING_TYPES')) {"
Replace-ExactlyOnce $mutationPath $old $new

$old = "    foreach (`$scenario in @('SECRET_BASE64','SECRET_URL')) {"
$new = "    foreach (`$scenario in @('SECRET_BASE64','SECRET_URL','SECRET_URL_LOWERHEX')) {"
Replace-ExactlyOnce $mutationPath $old $new

# Focused gates before publishing.
& pwsh -NoLogo -NoProfile -NonInteractive -File tests/EngineHost/Test-FakeEngineDirect.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& pwsh -NoLogo -NoProfile -NonInteractive -File tests/EngineHost/Test-EngineHostFingerprints.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& pwsh -NoLogo -NoProfile -NonInteractive -File tests/EngineHost/Test-EngineHost.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& pwsh -NoLogo -NoProfile -NonInteractive -File tests/EngineHost/Test-EngineHostMutations.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& pwsh -NoLogo -NoProfile -NonInteractive -File tests/EngineHost/Test-EngineHostSourceMutations.ps1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Remove the disposable driver/workflow from the final tree.
git rm -- '.github/scripts/fix-engine-host-final-review.ps1' '.github/workflows/fix-engine-host-final-review.yml'
git add -- $hostPath $fakePath $mutationPath
if ((git diff --cached --name-only) -notcontains $hostPath) { throw 'Host patch was not staged.' }

git config user.name 'atsisqual'
git config user.email 'alexandre.teixeira@sisqual.com'
git commit -m 'runtime: close final engine host review gaps'
git push origin HEAD:engine-host/adr-0008-runtime
