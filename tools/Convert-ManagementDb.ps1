#requires -Version 7.0
<#
.SYNOPSIS
    C1/C2 instance-directory entry point for Convert-ManagementDb.

.DESCRIPTION
    Keeps the proven converter in Convert-ManagementDb.Core.ps1 and adds the derived
    cfg_LinksPageDirectory table required by general Links pages. The directory contains
    public cross-machine instance data only; complete dbo_ManagedInstance rows remain local
    to exactly one catalog.
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

$script:C1C2ShouldExecute = ($MyInvocation.InvocationName -ne '.')
$script:C1C2Cli = [ordered]@{
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

$script:ToolVersion = '0.3.1'
$script:CutRuleVersion = 2
$script:LinksPageDirectoryTable = 'cfg.LinksPageDirectory'
$script:CarriedTables[$script:LinksPageDirectoryTable] = 'D'

$script:C1C2CoreReadSyncSchema = ${function:Read-SyncSchema}
$script:C1C2CoreReadSqlServerSource = ${function:Read-SqlServerSource}
$script:C1C2CoreNewCatalogFile = ${function:New-CatalogFile}
$script:C1C2CoreNewCatalogManifestEntry = ${function:New-CatalogManifestEntry}
$script:C1C2CoreInvokeCutConversion = ${function:Invoke-CutConversion}
$script:C1C2CoreInvokeNewMachineConversion = ${function:Invoke-NewMachineConversion}
$script:C1C2Source = $null

function Copy-C1C2ColumnInfo {
    param(
        [Parameter(Mandatory)]$SourceColumn,
        [Parameter(Mandatory)][string]$Name
    )
    return [pscustomobject]@{
        Name = $Name
        Type = [string]$SourceColumn.Type
        Length = [int]$SourceColumn.Length
        Precision = [int]$SourceColumn.Precision
        Scale = [int]$SourceColumn.Scale
        Identity = $false
        Nullable = [bool]$SourceColumn.Nullable
    }
}

function Get-LinksPageDirectorySchema {
    param([Parameter(Mandatory)]$ManagedInstanceSchema)
    $map = [ordered]@{
        InstanceCode = 'InstanceCode'
        ServerCode = 'ServerCode'
        CountryCode = 'CountryCode'
        CustomerCode = 'CustomerCode'
        CustomerName = 'CustomerName'
        HostName = 'HostName'
        AssignedUserName = 'LinksAssignedUserName'
    }
    $columns = [System.Collections.Generic.List[object]]::new()
    foreach ($destination in $map.Keys) {
        $sourceName = $map[$destination]
        $sourceColumn = @($ManagedInstanceSchema.Columns | Where-Object { $_.Name -ceq $sourceName } | Select-Object -First 1)
        if ($sourceColumn.Count -ne 1) { throw ('dbo.ManagedInstance is missing required Links directory source column {0}.' -f $sourceName) }
        $columns.Add((Copy-C1C2ColumnInfo -SourceColumn $sourceColumn[0] -Name $destination))
    }
    return [pscustomobject]@{
        Table = $script:LinksPageDirectoryTable
        Columns = $columns.ToArray()
        PrimaryKey = @('InstanceCode')
    }
}

function Add-LinksPageDirectorySchema {
    param([Parameter(Mandatory)][hashtable]$Schema)
    if (-not $script:CarriedTables.Contains($script:LinksPageDirectoryTable)) { return $Schema }
    if (-not $Schema.ContainsKey('dbo.ManagedInstance')) { throw 'dbo.ManagedInstance schema is required for the Links page directory.' }
    $Schema[$script:LinksPageDirectoryTable] = Get-LinksPageDirectorySchema -ManagedInstanceSchema $Schema['dbo.ManagedInstance']
    return $Schema
}

function Read-SyncSchema {
    param([string]$Text, [string[]]$Tables)
    $sourceTables = @($Tables | Where-Object { $_ -cne $script:LinksPageDirectoryTable })
    $schema = & $script:C1C2CoreReadSyncSchema -Text $Text -Tables $sourceTables
    return (Add-LinksPageDirectorySchema -Schema $schema)
}

function Read-SqlServerSource {
    param([string]$Instance, [string]$DatabaseName, [string]$ClientPath, [string[]]$Tables, [switch]$TrustCertificate)
    $sourceTables = @($Tables | Where-Object { $_ -cne $script:LinksPageDirectoryTable })
    $source = & $script:C1C2CoreReadSqlServerSource -Instance $Instance -DatabaseName $DatabaseName -ClientPath $ClientPath -Tables $sourceTables -TrustCertificate:$TrustCertificate
    if ($script:CarriedTables.Contains($script:LinksPageDirectoryTable)) {
        [void](Add-LinksPageDirectorySchema -Schema $source.Schema)
        $source.Rows[$script:LinksPageDirectoryTable] = [System.Collections.Generic.List[object]]::new()
    }
    return $source
}

function Test-C1C2EnabledRow {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Row)
    return ($Row.Contains('IsEnabled') -and $null -ne $Row['IsEnabled'] -and [int]$Row['IsEnabled'] -eq 1)
}

function Get-LinksPageDirectoryRows {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$CatalogServerCode
    )
    $result = [System.Collections.Generic.List[object]]::new()
    if (-not $script:CarriedTables.Contains($script:LinksPageDirectoryTable)) { return $result.ToArray() }

    $localServer = @($Source.Rows['dbo.ManagedServer'] | Where-Object { [string]$_['ServerCode'] -ieq $CatalogServerCode })
    if ($localServer.Count -eq 0) { return $result.ToArray() }
    if ($localServer.Count -ne 1) { throw ('ServerCode {0} is ambiguous while building the Links page directory.' -f $CatalogServerCode) }
    if (-not (Test-C1C2EnabledRow -Row $localServer[0])) { return $result.ToArray() }

    $generalCountries = @{}
    foreach ($instance in $Source.Rows['dbo.ManagedInstance']) {
        if ([string]$instance['ServerCode'] -ine $CatalogServerCode) { continue }
        if (-not (Test-C1C2EnabledRow -Row $instance)) { continue }
        if (-not $instance.Contains('LinksIncludeAllInstances') -or [int]$instance['LinksIncludeAllInstances'] -ne 1) { continue }
        $country = [string]$instance['CountryCode']
        if ([string]::IsNullOrWhiteSpace($country) -or $country.Length -ne 2) { throw ('General Links page instance {0} has an invalid CountryCode.' -f $instance['InstanceCode']) }
        $generalCountries[$country.ToLowerInvariant()] = $true
    }
    if ($generalCountries.Count -eq 0) { return $result.ToArray() }

    $enabledServers = @{}
    foreach ($server in $Source.Rows['dbo.ManagedServer']) {
        if (-not (Test-C1C2EnabledRow -Row $server)) { continue }
        $serverCode = [string]$server['ServerCode']
        if (-not [string]::IsNullOrWhiteSpace($serverCode)) { $enabledServers[$serverCode.ToLowerInvariant()] = $true }
    }

    foreach ($instance in $Source.Rows['dbo.ManagedInstance']) {
        $targetServer = [string]$instance['ServerCode']
        if ([string]::IsNullOrWhiteSpace($targetServer) -or $targetServer -ieq $CatalogServerCode) { continue }
        if (-not $enabledServers.ContainsKey($targetServer.ToLowerInvariant())) { continue }
        if (-not (Test-C1C2EnabledRow -Row $instance)) { continue }
        $country = [string]$instance['CountryCode']
        if ([string]::IsNullOrWhiteSpace($country) -or -not $generalCountries.ContainsKey($country.ToLowerInvariant())) { continue }

        $instanceCode = [string]$instance['InstanceCode']
        $hostName = [string]$instance['HostName']
        if ([string]::IsNullOrWhiteSpace($instanceCode)) { throw 'An enabled remote Links target has an empty InstanceCode.' }
        if ($country.Length -ne 2) { throw ('Remote Links target {0} has an invalid CountryCode.' -f $instanceCode) }
        if ([string]::IsNullOrWhiteSpace($hostName)) { throw ('Remote Links target {0} has an empty HostName.' -f $instanceCode) }

        $customerCode = $null
        if ($instance.Contains('CustomerCode')) { $customerCode = $instance['CustomerCode'] }
        $customerName = $null
        if ($instance.Contains('CustomerName')) { $customerName = $instance['CustomerName'] }
        $assignedUserName = $null
        if ($instance.Contains('LinksAssignedUserName')) { $assignedUserName = $instance['LinksAssignedUserName'] }
        $result.Add([ordered]@{
            InstanceCode = $instanceCode
            ServerCode = $targetServer
            CountryCode = $country
            CustomerCode = $customerCode
            CustomerName = $customerName
            HostName = $hostName
            AssignedUserName = $assignedUserName
        })
    }

    return @($result | Sort-Object `
        @{ Expression = { [string]$_['CountryCode'] } }, `
        @{ Expression = { if ($null -eq $_['CustomerCode']) { [long]::MaxValue } else { [long]$_['CustomerCode'] } } }, `
        @{ Expression = { [string]$_['InstanceCode'] } })
}

function New-CatalogFile {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][hashtable]$Schema,
        [Parameter(Mandatory)][hashtable]$Rows,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$SourceKind,
        [string]$SourceRef,
        [bool]$UseCodeCollation
    )
    if ($script:CarriedTables.Contains($script:LinksPageDirectoryTable)) {
        if (-not $Schema.ContainsKey($script:LinksPageDirectoryTable)) { [void](Add-LinksPageDirectorySchema -Schema $Schema) }
        $directory = [System.Collections.Generic.List[object]]::new()
        if ($null -ne $script:C1C2Source) {
            foreach ($row in @(Get-LinksPageDirectoryRows -Source $script:C1C2Source -CatalogServerCode $Code)) { $directory.Add($row) }
        }
        $Rows[$script:LinksPageDirectoryTable] = $directory
        Assert-NoSecretLiterals -Rows @{ $script:LinksPageDirectoryTable = $directory }
    }
    return (& $script:C1C2CoreNewCatalogFile @PSBoundParameters)
}

function New-CatalogManifestEntry {
    param([string]$Code, $Catalog, $Redacted, $Findings, [hashtable]$Extra = @{})
    $entry = & $script:C1C2CoreNewCatalogManifestEntry @PSBoundParameters
    if ($script:CarriedTables.Contains($script:LinksPageDirectoryTable)) {
        $row = @($Catalog.Tables | Where-Object { $_.table -ceq 'cfg_LinksPageDirectory' })
        $count = 0
        if ($row.Count -eq 1) { $count = [int]$row[0].destinationRows }
        $entry['linksPageDirectoryCount'] = $count
    }
    return $entry
}

function Invoke-CutConversion {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][hashtable]$SourceInfo,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string[]]$Codes = @('ALL'),
        [string]$SourceRef,
        [bool]$UseCodeCollation = $false
    )
    $script:C1C2Source = $Source
    $previousCutRuleVersion = $script:CutRuleVersion
    $script:CutRuleVersion = $(if ($script:CarriedTables.Contains($script:LinksPageDirectoryTable)) { 2 } else { 1 })
    try { return (& $script:C1C2CoreInvokeCutConversion @PSBoundParameters) }
    finally {
        $script:CutRuleVersion = $previousCutRuleVersion
        $script:C1C2Source = $null
    }
}

function Invoke-NewMachineConversion {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][hashtable]$SourceInfo,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Machine,
        [Parameter(Mandatory)][string]$Services,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$SourceRef,
        [bool]$UseCodeCollation = $false
    )
    $script:C1C2Source = $Source
    $previousCutRuleVersion = $script:CutRuleVersion
    $script:CutRuleVersion = $(if ($script:CarriedTables.Contains($script:LinksPageDirectoryTable)) { 2 } else { 1 })
    try { return (& $script:C1C2CoreInvokeNewMachineConversion @PSBoundParameters) }
    finally {
        $script:CutRuleVersion = $previousCutRuleVersion
        $script:C1C2Source = $null
    }
}

if ($script:C1C2ShouldExecute) {
    $cli = $script:C1C2Cli
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
