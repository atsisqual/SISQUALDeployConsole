#requires -Version 7.0
<#
.SYNOPSIS
    The preflight engine and the synthetic catalog of its tests must use the real catalog schema.

.DESCRIPTION
    The engine was first written and tested against a catalog whose columns the author had invented (BackendUrlTemplate, BinaryContent on assets),
    so every test passed and the engine could not read a real catalog. This test compares every table the engine names, every field it reads, and
    every table and column of the synthetic catalog in Test-DeploymentPreflight.ps1 with tests/Fixtures/carried-schema.json (the shape of the 62
    tables carried into the catalogs).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:Passed = 0; $script:Failed = 0
function Check([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:Passed++; Write-Host ('PASS  ' + $Name) }
    else { $script:Failed++; Write-Host ('FAIL  ' + $Name + $(if ($Detail) { ' - ' + $Detail } else { '' })) }
}

$schema = Get-Content -LiteralPath (Join-Path $repo 'tests/Fixtures/carried-schema.json') -Raw | ConvertFrom-Json -Depth 20
$columns = @{}
foreach ($table in $schema.tables) {
    $name = ([string]$table.table) -replace '\.', '_'
    $columns[$name] = [Collections.Generic.HashSet[string]]::new([string[]]@($table.columns | ForEach-Object { [string]$_.name }), [StringComparer]::Ordinal)
}
# catalog_meta is written by the converter, not carried from the source database.
$generated = @('catalog_meta')

$engineText = Get-Content -LiteralPath (Join-Path $repo 'engines/Invoke-DeploymentPreflight.ps1') -Raw
$engineTables = @([regex]::Matches($engineText, "'((?:cfg|dbo|ops|catalog)_[A-Za-z0-9]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$unknownTables = @($engineTables | Where-Object { -not $columns.ContainsKey($_) -and $generated -cnotcontains $_ })
Check 'every table the engine names is in the carried schema' ($unknownTables.Count -eq 0) ($unknownTables -join ', ')

$known = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($table in $engineTables) { if ($columns.ContainsKey($table)) { foreach ($column in $columns[$table]) { [void]$known.Add($column) } } }
# Names that are not catalog columns: the request, the package manifest and the catalog_meta row.
$notCatalog = @('contractVersion','operationId','engineCode','mode','catalogPath','planFingerprint','instanceCode','deadlineUtc','cancelPath','resultPath','secrets','path','sha256','size','built_at_utc')
$fields = @([regex]::Matches($engineText, "Get-Field\s+\`$[A-Za-z_]+(?:\.[A-Za-z_]+)?\s+'([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$unknownFields = @($fields | Where-Object { $notCatalog -cnotcontains $_ -and -not $known.Contains($_) })
Check 'every field the engine reads is a column of a table it uses' ($unknownFields.Count -eq 0) ($unknownFields -join ', ')

$testText = Get-Content -LiteralPath (Join-Path $repo 'tests/EngineHost/Test-DeploymentPreflight.ps1') -Raw
$badColumns = [Collections.Generic.List[string]]::new()
$badTables = [Collections.Generic.List[string]]::new()
foreach ($match in [regex]::Matches($testText, 'CREATE TABLE\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)')) {
    $table = $match.Groups[1].Value
    if ($generated -ccontains $table) { continue }
    if (-not $columns.ContainsKey($table)) { $badTables.Add($table); continue }
    foreach ($definition in ($match.Groups[2].Value -split ',')) {
        $column = ($definition.Trim() -split '\s+')[0]
        if ($column -and -not $columns[$table].Contains($column)) { $badColumns.Add($table + '.' + $column) }
    }
}
Check 'every table of the synthetic catalog is a carried table' ($badTables.Count -eq 0) ($badTables -join ', ')
Check 'every column of the synthetic catalog is a real column' ($badColumns.Count -eq 0) ($badColumns -join ', ')
Check 'the engine reads at least the tables of the reviews it implements' ($engineTables.Count -ge 20) ([string]$engineTables.Count)


$declaredTables = @([regex]::Matches(([regex]::Match($engineText, '\$script:RequiredCatalogTables = @\(([^)]*)\)').Groups[1].Value), "'([A-Za-z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$readTables = @($engineTables | Where-Object { $_ -cne 'catalog_meta' })
Check 'the engine requires exactly the tables it reads (catalog_meta aside)' (($declaredTables -join ',') -ceq ($readTables -join ',')) (('required {0} / read {1}' -f $declaredTables.Count, $readTables.Count))
$syntheticTables = @([regex]::Matches($testText, 'CREATE TABLE\s+([A-Za-z0-9_]+)\s*\(') | ForEach-Object { $_.Groups[1].Value })
$notBuilt = @($declaredTables | Where-Object { $syntheticTables -cnotcontains $_ })
Check 'the synthetic catalog creates every table the engine requires' ($notBuilt.Count -eq 0) ($notBuilt -join ', ')

# Coverage of the original reviews. The fixture lists the issue codes of the original review procedures; the engine says how many it implements, and
# the numbers must agree with the source, so an engine can never claim more coverage than it has (or forget to say it has less).
$fixture = Get-Content -LiteralPath (Join-Path $repo 'tests/Fixtures/preflight-legacy-codes.json') -Raw | ConvertFrom-Json -Depth 20
$engineSeverity = @{}
foreach ($match in [regex]::Matches($engineText, 'Add-Issue\s+(ERROR|WARNING|INFO)\s+[A-Z_]+\s+([A-Z][A-Z0-9_]+)')) {
    if (-not $engineSeverity.ContainsKey($match.Groups[2].Value)) { $engineSeverity[$match.Groups[2].Value] = [Collections.Generic.HashSet[string]]::new() }
    [void]$engineSeverity[$match.Groups[2].Value].Add($match.Groups[1].Value)
}
$implemented = @($fixture.codes | Where-Object { $engineSeverity.ContainsKey([string]$_.code) })
$missing = @($fixture.codes | Where-Object { -not $engineSeverity.ContainsKey([string]$_.code) })
$declaredImplemented = [int]([regex]::Match($engineText, '\$script:CoverageImplemented = (\d+)').Groups[1].Value)
$declaredTotal = [int]([regex]::Match($engineText, '\$script:CoverageTotal = (\d+)').Groups[1].Value)
Check 'the engine declares exactly how many of the original issue codes it implements' ($declaredImplemented -eq $implemented.Count -and $declaredTotal -eq @($fixture.codes).Count) ("declared $declaredImplemented of $declaredTotal; source $($implemented.Count) of $(@($fixture.codes).Count)")
$overrides = @{}; foreach ($override in $fixture.ownerSeverityOverrides) { $overrides[[string]$override.code] = [string]$override.engine }
$wrongSeverity = @($implemented | Where-Object { $expected = if ($overrides.ContainsKey([string]$_.code)) { $overrides[[string]$_.code] } else { [string]$_.severity }; -not ($engineSeverity[[string]$_.code].Count -eq 1 -and $engineSeverity[[string]$_.code].Contains($expected)) } | ForEach-Object { [string]$_.code })
Check 'every implemented issue code has the severity of the original review (or an owner decision)' ($wrongSeverity.Count -eq 0) ($wrongSeverity -join ', ')
foreach ($group in ($missing | Group-Object review)) { Write-Host ('DIAG  not yet ported from {0}: {1}' -f $group.Name, (($group.Group | ForEach-Object { [string]$_.code }) -join ', ')) }

Write-Host ('Preflight schema conformance: {0} passed / {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
