#requires -Version 7.0
<#
.SYNOPSIS
    Verifies catalogs written by Convert-ManagementDb.ps1, including C8 action cross-references.

.DESCRIPTION
    Keeps the proven B4 verifier in Test-CatalogConversion.Core.ps1 and adds the C8 / R-043
    fail-closed cross-reference checks without changing the existing value, cut, secret or hash checks.

    C8 validates, with exact BINARY/ordinal semantics:
      cfg_ConfigurationAdapterDefinition.ActionCode -> ops_Action.ActionCode
      ops_Action.EngineCode -> ops_Engine.EngineCode

    NULL or blank adapter ActionCode and NULL or blank action EngineCode are intentionally allowed.
    Identifier mismatches are reported by code only; no configuration values or secrets are printed.
#>
[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Sync')][string]$SyncFile,
    [Parameter(Mandatory, ParameterSetName = 'Sql')][string]$SqlInstance,
    [Parameter(ParameterSetName = 'Sql')][string]$Database = '_sisqualMANAGEMENT',
    [Parameter(Mandatory, ParameterSetName = 'Sql')][string]$SqlClientPath,
    [Parameter(ParameterSetName = 'Sql')][switch]$TrustServerCertificate,
    [Parameter(Mandatory)][string]$CatalogFolder,
    [Parameter(Mandatory)][string]$Sqlite3Path,
    [string]$ReportPath = '',
    [string[]]$ExtraNeedle = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:C8ShouldExecute = ($MyInvocation.InvocationName -ne '.')
$script:C8Cli = [ordered]@{
    ParameterSet = $PSCmdlet.ParameterSetName
    SyncFile = $SyncFile
    SqlInstance = $SqlInstance
    Database = $Database
    SqlClientPath = $SqlClientPath
    TrustServerCertificate = [bool]$TrustServerCertificate
    CatalogFolder = $CatalogFolder
    Sqlite3Path = $Sqlite3Path
    ReportPath = $ReportPath
    ExtraNeedle = @($ExtraNeedle)
}

$corePath = Join-Path $PSScriptRoot 'Test-CatalogConversion.Core.ps1'
. $corePath -SyncFile 'unused' -CatalogFolder 'unused' -Sqlite3Path 'unused'

$script:C8LegacyInvokeCatalogConversionTest = ${function:Invoke-CatalogConversionTest}
$script:TestToolVersion = '0.2.0'

function Get-C8QueryLines {
    param(
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][string]$Sql
    )
    $out = Invoke-Sqlite3 -Exe $Sqlite3 -Arguments @('-readonly', $DatabasePath, $Sql)
    return @($out -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_.Length -gt 0 })
}

function Test-C8CatalogHasTables {
    param(
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$DatabasePath
    )
    $required = @('cfg_ConfigurationAdapterDefinition', 'ops_Action', 'ops_Engine')
    $sql = "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('cfg_ConfigurationAdapterDefinition','ops_Action','ops_Engine') ORDER BY name;"
    $actual = @(Get-C8QueryLines -Sqlite3 $Sqlite3 -DatabasePath $DatabasePath -Sql $sql)
    return (@($required | Where-Object { $actual -notcontains $_ }).Count -eq 0)
}

function Add-C8ActionCrossReferenceChecks {
    param(
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)]$Entries
    )

    foreach ($entry in @($Entries)) {
        $code = [string]$entry.serverCode
        $databasePath = Join-Path $Folder ([string]$entry.file)
        if (-not (Test-Path -LiteralPath $databasePath -PathType Leaf)) { continue }
        if (-not (Test-C8CatalogHasTables -Sqlite3 $Sqlite3 -DatabasePath $databasePath)) { continue }

        $adapterSql = @"
SELECT a.AdapterCode || '->' || a.ActionCode
FROM cfg_ConfigurationAdapterDefinition AS a
LEFT JOIN ops_Action AS x
  ON x.ActionCode COLLATE BINARY = a.ActionCode COLLATE BINARY
WHERE a.ActionCode IS NOT NULL
  AND length(trim(a.ActionCode)) > 0
  AND x.ActionCode IS NULL
ORDER BY a.AdapterCode;
"@
        $adapterMissing = @(Get-C8QueryLines -Sqlite3 $Sqlite3 -DatabasePath $databasePath -Sql $adapterSql)
        $adapterDetail = ''
        if ($adapterMissing.Count -gt 0) {
            $adapterDetail = (($adapterMissing | Select-Object -First 5) -join ', ')
            if ($adapterMissing.Count -gt 5) { $adapterDetail += ' ...' }
        }
        Add-Check 'action-xref' ('{0}: every non-empty adapter ActionCode resolves exactly to ops_Action' -f $code) ($adapterMissing.Count -eq 0) $adapterDetail

        $engineSql = @"
SELECT a.ActionCode || '->' || a.EngineCode
FROM ops_Action AS a
LEFT JOIN ops_Engine AS e
  ON e.EngineCode COLLATE BINARY = a.EngineCode COLLATE BINARY
WHERE a.EngineCode IS NOT NULL
  AND length(trim(a.EngineCode)) > 0
  AND e.EngineCode IS NULL
ORDER BY a.ActionCode;
"@
        $engineMissing = @(Get-C8QueryLines -Sqlite3 $Sqlite3 -DatabasePath $databasePath -Sql $engineSql)
        $engineDetail = ''
        if ($engineMissing.Count -gt 0) {
            $engineDetail = (($engineMissing | Select-Object -First 5) -join ', ')
            if ($engineMissing.Count -gt 5) { $engineDetail += ' ...' }
        }
        Add-Check 'action-xref' ('{0}: every non-empty ops_Action.EngineCode resolves exactly to ops_Engine' -f $code) ($engineMissing.Count -eq 0) $engineDetail
    }
}

function Invoke-CatalogConversionTest {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string[]]$ExtraNeedles = @()
    )

    $legacy = & $script:C8LegacyInvokeCatalogConversionTest -Source $Source -Folder $Folder -Sqlite3 $Sqlite3 -ExtraNeedles $ExtraNeedles
    if ($legacy.Catalogs -le 0 -or [string]::IsNullOrWhiteSpace([string]$legacy.Mode)) { return $legacy }

    $manifestPath = Join-Path $Folder 'conversion-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $legacy }
    try {
        $manifest = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($manifestPath)) | ConvertFrom-Json
        Add-C8ActionCrossReferenceChecks -Folder $Folder -Sqlite3 $Sqlite3 -Entries @($manifest.catalogs)
    }
    catch {
        Add-Check 'action-xref' 'C8 action cross-reference check completed without an internal error' $false $_.Exception.Message
    }

    return (New-TestResult -Mode $legacy.Mode -Catalogs $legacy.Catalogs)
}

if ($script:C8ShouldExecute) {
    $cli = $script:C8Cli
    $tables = @($script:CarriedTables.Keys)
    if ($cli.ParameterSet -eq 'Sync') {
        $resolved = (Resolve-Path -LiteralPath $cli.SyncFile).Path
        Write-Host ('Reading {0}...' -f (Split-Path -Leaf $resolved))
        $text = [System.IO.File]::ReadAllText($resolved, [System.Text.UTF8Encoding]::new($false))
        $schema = Read-SyncSchema -Text $text -Tables $tables
        $source = [pscustomobject]@{ Schema = $schema; Rows = (Read-SyncRows -Text $text -Schema $schema) }
    }
    else {
        $source = Read-SqlServerSource -Instance $cli.SqlInstance -DatabaseName $cli.Database -ClientPath $cli.SqlClientPath -Tables $tables -TrustCertificate:$cli.TrustServerCertificate
    }
    $result = Invoke-CatalogConversionTest -Source $source -Folder $cli.CatalogFolder -Sqlite3 $cli.Sqlite3Path -ExtraNeedles $cli.ExtraNeedle
    Write-Host ('{0} passed, {1} failed ({2} mode, {3} catalog(s))' -f $result.Passed, $result.Failed, $result.Mode, $result.Catalogs)
    if ($cli.ReportPath) { Write-TestReport -Result $result -Path $cli.ReportPath }
    if ($result.Failed -gt 0) { exit 1 }
}
