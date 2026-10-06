#requires -Version 7.0
<#
.SYNOPSIS
    C7 structured-filter entry point for Convert-ManagementDb.

.DESCRIPTION
    Keeps the proven conversion implementation in Convert-ManagementDb.Core.ps1 and overlays
    catalog schema v2: cfg.DatabaseObjectSettingRule.FilterClause is converted once into
    FilterPredicateJson and raw SQL is not carried into the catalog. Unsupported filters fail closed.
#>
[CmdletBinding(DefaultParameterSetName = 'Sync')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Sync')][string]$SyncFile,
    [Parameter(Mandatory, ParameterSetName = 'Sql')][string]$SqlInstance,
    [Parameter(ParameterSetName = 'Sql')][string]$Database = '_sisqualMANAGEMENT',
    [Parameter(Mandatory, ParameterSetName = 'Sql')][string]$SqlClientPath,
    [Parameter(ParameterSetName = 'Sql')][switch]$TrustServerCertificate,
    [Parameter(Mandatory)][string]$OutputFolder,
    [Parameter(Mandatory)][string]$Sqlite3Path,
    [switch]$NewMachine,
    [string[]]$ServerCode,
    [string]$MachineName,
    [string]$ServicesRoot,
    [string]$ConfigBackupRoot,
    [string]$SourceReference = '',
    [ValidateSet('Binary', 'NoCase')][string]$CodeCollation = 'Binary'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:C7ShouldExecute = ($MyInvocation.InvocationName -ne '.')
$script:C7Cli = [ordered]@{
    ParameterSet = $PSCmdlet.ParameterSetName
    SyncFile = $SyncFile
    SqlInstance = $SqlInstance
    Database = $Database
    SqlClientPath = $SqlClientPath
    TrustServerCertificate = [bool]$TrustServerCertificate
    OutputFolder = $OutputFolder
    Sqlite3Path = $Sqlite3Path
    NewMachine = [bool]$NewMachine
    ServerCode = @($ServerCode)
    MachineName = $MachineName
    ServicesRoot = $ServicesRoot
    ConfigBackupRoot = $ConfigBackupRoot
    SourceReference = $SourceReference
    CodeCollation = $CodeCollation
}

$corePath = Join-Path $PSScriptRoot 'Convert-ManagementDb.Core.ps1'
$coreArgs = @{ OutputFolder = $OutputFolder; Sqlite3Path = $Sqlite3Path; CodeCollation = $CodeCollation; SourceReference = $SourceReference }
if ($PSCmdlet.ParameterSetName -eq 'Sync') { $coreArgs['SyncFile'] = $SyncFile }
else {
    $coreArgs['SqlInstance'] = $SqlInstance
    $coreArgs['Database'] = $Database
    $coreArgs['SqlClientPath'] = $SqlClientPath
    if ($TrustServerCertificate) { $coreArgs['TrustServerCertificate'] = $true }
}
if ($NewMachine) { $coreArgs['NewMachine'] = $true }
if (@($ServerCode).Count -gt 0) { $coreArgs['ServerCode'] = @($ServerCode) }
if (-not [string]::IsNullOrWhiteSpace($MachineName)) { $coreArgs['MachineName'] = $MachineName }
if (-not [string]::IsNullOrWhiteSpace($ServicesRoot)) { $coreArgs['ServicesRoot'] = $ServicesRoot }
if (-not [string]::IsNullOrWhiteSpace($ConfigBackupRoot)) { $coreArgs['ConfigBackupRoot'] = $ConfigBackupRoot }
. $corePath @coreArgs
. (Join-Path $PSScriptRoot 'Convert-DatabaseFilter.ps1')

# Catalog schema v2 removes executable FilterClause SQL and replaces it with deterministic JSON.
$script:ToolVersion = '0.4.0'
$script:SchemaVersion = 2
$script:CutRuleVersion = 2
$script:CatalogExcludedColumns = @{
    'cfg.DatabaseObjectSettingRule' = @('FilterClause')
}

$script:C7LegacyReadSyncRows = ${function:Read-SyncRows}
$script:C7LegacyReadSqlServerSource = ${function:Read-SqlServerSource}

function Convert-C7DatabaseObjectRules {
    param([Parameter(Mandatory)][hashtable]$Rows)
    if (-not $Rows.ContainsKey('cfg.DatabaseObjectSettingRule')) { return $Rows }
    foreach ($row in $Rows['cfg.DatabaseObjectSettingRule']) {
        [void](Convert-DatabaseObjectSettingRuleForCatalog -Row $row)
    }
    return $Rows
}

function Read-SyncRows {
    param([string]$Text, [hashtable]$Schema)
    $rows = & $script:C7LegacyReadSyncRows -Text $Text -Schema $Schema
    return (Convert-C7DatabaseObjectRules -Rows $rows)
}

function Read-SqlServerSource {
    param([string]$Instance, [string]$DatabaseName, [string]$ClientPath, [string[]]$Tables, [switch]$TrustCertificate)
    $source = & $script:C7LegacyReadSqlServerSource -Instance $Instance -DatabaseName $DatabaseName -ClientPath $ClientPath -Tables $Tables -TrustCertificate:$TrustCertificate
    [void](Convert-C7DatabaseObjectRules -Rows $source.Rows)
    return $source
}

function Get-CarriedColumns {
    param([string]$Table, $TableSchema)
    $skip = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($script:ExcludedColumns[$Table])) { if (-not [string]::IsNullOrWhiteSpace($name)) { $skip.Add($name) } }
    foreach ($name in @($script:CatalogExcludedColumns[$Table])) { if (-not [string]::IsNullOrWhiteSpace($name)) { $skip.Add($name) } }
    $columns = [System.Collections.Generic.List[object]]::new()
    foreach ($column in $TableSchema.Columns) {
        if ($column.Type -in @('timestamp', 'rowversion') -or $skip.Contains($column.Name)) { continue }
        $columns.Add($column)
    }
    if ($Table -ceq 'cfg.DatabaseObjectSettingRule') { $columns.Add((Get-StructuredDatabaseFilterColumnInfo)) }
    return , $columns.ToArray()
}

function Get-ExcludedColumnList {
    $excluded = [System.Collections.Generic.List[string]]::new()
    foreach ($map in @($script:ExcludedColumns, $script:CatalogExcludedColumns)) {
        foreach ($table in $map.Keys) {
            foreach ($column in @($map[$table])) { $excluded.Add(('{0}.{1}' -f $table, $column)) }
        }
    }
    return , $excluded.ToArray()
}

function Write-ConversionManifest {
    param([string]$Folder, [string]$Mode, [string]$BuiltAtUtc, [hashtable]$SourceInfo, [bool]$UseCodeCollation, $Entries, [hashtable]$Extra = @{})
    $manifest = [ordered]@{
        contractVersion = '0.2-proposed'
        tool = 'Convert-ManagementDb'
        toolVersion = $script:ToolVersion
        mode = $Mode
        convertedAtUtc = $BuiltAtUtc
        source = $SourceInfo
        codeCollation = $(if ($UseCodeCollation) { 'NOCASE' } else { 'BINARY' })
        sourceCollation = $(if ($SourceInfo.ContainsKey('collation')) { [string]$SourceInfo['collation'] } else { 'not available from an offline file; the owner states Latin1_General_CI_AS (2026-10-05) [V]' })
        catalogs = @($Entries)
        excludedTableCount = 55
        structuredDatabaseFilters = [ordered]@{
            version = 1
            sourceColumn = 'cfg.DatabaseObjectSettingRule.FilterClause'
            catalogColumn = 'cfg_DatabaseObjectSettingRule.FilterPredicateJson'
            rawSqlCarried = $false
        }
    }
    foreach ($key in $Extra.Keys) { $manifest[$key] = $Extra[$key] }
    $json = ($manifest | ConvertTo-Json -Depth 16 -EscapeHandling EscapeNonAscii)
    $json = ($json -replace "`r`n", "`n") + "`n"
    $path = Join-Path $Folder 'conversion-manifest.json'
    [System.IO.File]::WriteAllBytes($path, [System.Text.UTF8Encoding]::new($false).GetBytes($json))
    return $path
}

if ($script:C7ShouldExecute) {
    $cli = $script:C7Cli
    if ($cli.NewMachine) {
        if (@($cli.ServerCode | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -ne 1) { throw '-NewMachine needs exactly one -ServerCode.' }
        foreach ($required in @('MachineName', 'ServicesRoot', 'ConfigBackupRoot')) {
            if ([string]::IsNullOrWhiteSpace([string]$cli[$required])) { throw ('-{0} is required with -NewMachine.' -f $required) }
        }
    }
    else {
        foreach ($notAllowed in @('MachineName', 'ServicesRoot', 'ConfigBackupRoot')) {
            if (-not [string]::IsNullOrWhiteSpace([string]$cli[$notAllowed])) { throw ('-{0} is only valid with -NewMachine.' -f $notAllowed) }
        }
    }

    $tables = @($script:CarriedTables.Keys)
    if ($cli.ParameterSet -eq 'Sync') {
        $resolved = (Resolve-Path -LiteralPath $cli.SyncFile).Path
        $item = Get-Item -LiteralPath $resolved
        Write-Host ('Reading {0} ({1} bytes)...' -f $item.Name, $item.Length)
        $text = [System.IO.File]::ReadAllText($resolved, [System.Text.UTF8Encoding]::new($false))
        $schema = Read-SyncSchema -Text $text -Tables $tables
        $rows = Read-SyncRows -Text $text -Schema $schema
        $source = [pscustomobject]@{ Schema = $schema; Rows = $rows }
        $info = @{ kind = 'sync-file'; fileName = $item.Name; fileBytes = $item.Length; fileSha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    else {
        $source = Read-SqlServerSource -Instance $cli.SqlInstance -DatabaseName $cli.Database -ClientPath $cli.SqlClientPath -Tables $tables -TrustCertificate:$cli.TrustServerCertificate
        $info = @{ kind = 'sql-server'; instance = $cli.SqlInstance; database = $cli.Database; readOnly = $true; trustServerCertificate = [bool]$cli.TrustServerCertificate; collation = $source.Collation }
    }

    $noCase = ($cli.CodeCollation -eq 'NoCase')
    if ($cli.NewMachine) {
        $result = Invoke-NewMachineConversion -Source $source -SourceInfo $info -Folder $cli.OutputFolder -Sqlite3 $cli.Sqlite3Path -Code $cli.ServerCode[0] -Machine $cli.MachineName -Services $cli.ServicesRoot -BackupRoot $cli.ConfigBackupRoot -SourceRef $cli.SourceReference -UseCodeCollation $noCase
        Write-Host ('Catalog: {0}' -f $result.Catalog)
    }
    else {
        $codes = @($cli.ServerCode | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($codes.Count -eq 0) { $codes = @('ALL') }
        $result = Invoke-CutConversion -Source $source -SourceInfo $info -Folder $cli.OutputFolder -Sqlite3 $cli.Sqlite3Path -Codes $codes -SourceRef $cli.SourceReference -UseCodeCollation $noCase
        Write-Host ('Catalogs: {0}' -f @($result.Catalogs).Count)
        foreach ($finding in $result.Unplaced) { Write-Host ('Finding: {0}' -f $finding) }
    }
    Write-Host ('Manifest: {0}' -f $result.Manifest)
    Write-Host ('Redacted rule templates: {0}' -f $result.Redacted)
}
