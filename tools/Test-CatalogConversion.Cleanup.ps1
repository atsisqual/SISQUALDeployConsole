#requires -Version 7.0
# PR #59 verifier layer, loaded after main's C8 + C1/C2 wrappers.
$script:CleanupVerifierMainInvokeCatalogConversionTest = ${function:Invoke-CatalogConversionTest}
function Get-CleanupManifestProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-CleanupIntegerEquals {
    param($Value, [Parameter(Mandatory)][int]$Expected)
    if ($null -eq $Value) { return $false }
    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed)) { return $false }
    return ($parsed -eq $Expected)
}

function Add-CleanupManifestChecks {
    param([Parameter(Mandatory)]$Manifest)

    $issues = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-CleanupIntegerEquals -Value (Get-CleanupManifestProperty -Object $Manifest -Name 'excludedTableCount') -Expected 56)) { $issues.Add('excludedTableCount') }

    $retired = Get-CleanupManifestProperty -Object $Manifest -Name 'retiredCatalogMetadata'
    if ($null -eq $retired) {
        $issues.Add('retiredCatalogMetadata')
    }
    else {
        if (-not (Test-CleanupIntegerEquals -Value (Get-CleanupManifestProperty -Object $retired -Name 'version') -Expected 1)) { $issues.Add('version') }
        if ([string](Get-CleanupManifestProperty -Object $retired -Name 'excludedSourceTable') -cne 'cfg.DatabaseSettingRule') { $issues.Add('excludedSourceTable') }
        if ([string](Get-CleanupManifestProperty -Object $retired -Name 'removedActionCode') -cne 'V8_KEYCLOAK_CONFIG') { $issues.Add('removedActionCode') }
        $engines = @(Get-CleanupManifestProperty -Object $retired -Name 'removedEngineCodes')
        if ($engines.Count -ne 2 -or -not ($engines -ccontains 'DATABASE_SETTINGS') -or -not ($engines -ccontains 'V8_KEYCLOAK_CONFIG')) { $issues.Add('removedEngineCodes') }
        if (-not (Test-CleanupIntegerEquals -Value (Get-CleanupManifestProperty -Object $retired -Name 'removedFullDeploymentStep') -Expected 63)) { $issues.Add('removedFullDeploymentStep') }
        if ([string](Get-CleanupManifestProperty -Object $retired -Name 'databaseSettingsActionEngine') -cne 'DATABASE_CONTENT_SYNC') { $issues.Add('databaseSettingsActionEngine') }
    }

    Add-Check 'retirement-metadata' 'conversion manifest records the approved obsolete-metadata transform' ($issues.Count -eq 0) (($issues | Select-Object -First 8) -join ', ')
}
function Test-CleanupManifestContractApplies {
    return ($script:CarriedTables.Count -eq 62 -and
        $script:CarriedTables.Contains('cfg.DatabaseObjectSettingRule') -and
        $script:CarriedTables.Contains('cfg.LinksPageDirectory') -and
        -not $script:CarriedTables.Contains('cfg.DatabaseSettingRule'))
}

function Invoke-CatalogConversionTest {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string[]]$ExtraNeedles = @()
    )
    $legacy = & $script:CleanupVerifierMainInvokeCatalogConversionTest @PSBoundParameters
    if ($legacy.Catalogs -le 0 -or [string]::IsNullOrWhiteSpace([string]$legacy.Mode)) { return $legacy }
    if (-not (Test-CleanupManifestContractApplies)) { return $legacy }

    $manifestPath = Join-Path $Folder 'conversion-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $legacy }
    try {
        $manifest = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($manifestPath)) | ConvertFrom-Json
        Add-CleanupManifestChecks -Manifest $manifest
    }
    catch {
        Add-Check 'retirement-metadata' 'retirement metadata check completed without an internal error' $false $_.Exception.Message
    }
    return (New-TestResult -Mode $legacy.Mode -Catalogs $legacy.Catalogs)
}
