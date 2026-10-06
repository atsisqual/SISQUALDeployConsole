#requires -Version 7.0
<#
.SYNOPSIS
    Verifies catalog conversion including the C1/C2 Links instance directory.

.DESCRIPTION
    Keeps the proven B4 verifier in Test-CatalogConversion.Core.ps1. The legacy checks run
    unchanged against the 62 source-carried tables, while this overlay independently recomputes
    and verifies the derived cfg_LinksPageDirectory table in every catalog.
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

$script:C1C2VerifierShouldExecute = ($MyInvocation.InvocationName -ne '.')
$script:C1C2VerifierCli = [ordered]@{
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

$script:C1C2CoreInvokeCatalogConversionTest = ${function:Invoke-CatalogConversionTest}
$script:C1C2CoreGetCatalogColumns = ${function:Get-CatalogColumns}
$script:C1C2HideDirectoryForCore = $false
$script:TestToolVersion = '0.2.0'

function Get-CatalogColumns {
    param([string]$Sqlite3, [string]$Db)
    $map = & $script:C1C2CoreGetCatalogColumns -Sqlite3 $Sqlite3 -Db $Db
    if ($script:C1C2HideDirectoryForCore -and $map.Contains('cfg_LinksPageDirectory')) {
        [void]$map.Remove('cfg_LinksPageDirectory')
    }
    return $map
}

function Get-C1C2VerifierDirectorySchema {
    param([Parameter(Mandatory)]$Source)
    if (-not $Source.Schema.ContainsKey('dbo.ManagedInstance')) { throw 'dbo.ManagedInstance schema is missing.' }
    $mapping = [ordered]@{
        InstanceCode = 'InstanceCode'
        ServerCode = 'ServerCode'
        CountryCode = 'CountryCode'
        CustomerCode = 'CustomerCode'
        CustomerName = 'CustomerName'
        HostName = 'HostName'
        AssignedUserName = 'LinksAssignedUserName'
    }
    $columns = [System.Collections.Generic.List[object]]::new()
    foreach ($destination in $mapping.Keys) {
        $sourceName = $mapping[$destination]
        $matches = @($Source.Schema['dbo.ManagedInstance'].Columns | Where-Object { $_.Name -ceq $sourceName })
        if ($matches.Count -ne 1) { throw ('dbo.ManagedInstance is missing directory source column {0}.' -f $sourceName) }
        $column = $matches[0]
        $columns.Add([pscustomobject]@{
            Name = $destination
            Type = [string]$column.Type
            Length = [int]$column.Length
            Precision = [int]$column.Precision
            Scale = [int]$column.Scale
            Identity = $false
            Nullable = [bool]$column.Nullable
        })
    }
    return [pscustomobject]@{ Table = 'cfg.LinksPageDirectory'; Columns = $columns.ToArray(); PrimaryKey = @('InstanceCode') }
}

function Get-C1C2ExpectedDirectoryRows {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$CatalogServerCode
    )
    $result = [System.Collections.Generic.List[object]]::new()
    $localServers = @($Source.Rows['dbo.ManagedServer'] | Where-Object { [string]$_['ServerCode'] -ieq $CatalogServerCode })
    if ($localServers.Count -eq 0) { return $result.ToArray() }
    if ($localServers.Count -ne 1) { throw ('ServerCode {0} is ambiguous in the source.' -f $CatalogServerCode) }
    $localEnabled = $localServers[0].Contains('IsEnabled') -and $null -ne $localServers[0]['IsEnabled'] -and [int]$localServers[0]['IsEnabled'] -eq 1
    if (-not $localEnabled) { return $result.ToArray() }

    $countries = @{}
    foreach ($instance in $Source.Rows['dbo.ManagedInstance']) {
        if ([string]$instance['ServerCode'] -ine $CatalogServerCode) { continue }
        $enabled = $instance.Contains('IsEnabled') -and $null -ne $instance['IsEnabled'] -and [int]$instance['IsEnabled'] -eq 1
        $general = $instance.Contains('LinksIncludeAllInstances') -and $null -ne $instance['LinksIncludeAllInstances'] -and [int]$instance['LinksIncludeAllInstances'] -eq 1
        if (-not ($enabled -and $general)) { continue }
        $country = [string]$instance['CountryCode']
        if ($country.Length -ne 2) { throw ('General page instance {0} has an invalid CountryCode.' -f $instance['InstanceCode']) }
        $countries[$country.ToLowerInvariant()] = $true
    }
    if ($countries.Count -eq 0) { return $result.ToArray() }

    $enabledServers = @{}
    foreach ($server in $Source.Rows['dbo.ManagedServer']) {
        if (-not ($server.Contains('IsEnabled') -and $null -ne $server['IsEnabled'] -and [int]$server['IsEnabled'] -eq 1)) { continue }
        $value = [string]$server['ServerCode']
        if ($value.Length -gt 0) { $enabledServers[$value.ToLowerInvariant()] = $true }
    }

    foreach ($instance in $Source.Rows['dbo.ManagedInstance']) {
        $serverCode = [string]$instance['ServerCode']
        if ($serverCode.Length -eq 0 -or $serverCode -ieq $CatalogServerCode) { continue }
        if (-not $enabledServers.ContainsKey($serverCode.ToLowerInvariant())) { continue }
        if (-not ($instance.Contains('IsEnabled') -and $null -ne $instance['IsEnabled'] -and [int]$instance['IsEnabled'] -eq 1)) { continue }
        $country = [string]$instance['CountryCode']
        if ($country.Length -eq 0 -or -not $countries.ContainsKey($country.ToLowerInvariant())) { continue }

        $customerCode = $null
        if ($instance.Contains('CustomerCode')) { $customerCode = $instance['CustomerCode'] }
        $customerName = $null
        if ($instance.Contains('CustomerName')) { $customerName = $instance['CustomerName'] }
        $assignedUser = $null
        if ($instance.Contains('LinksAssignedUserName')) { $assignedUser = $instance['LinksAssignedUserName'] }
        $result.Add([ordered]@{
            InstanceCode = [string]$instance['InstanceCode']
            ServerCode = $serverCode
            CountryCode = $country
            CustomerCode = $customerCode
            CustomerName = $customerName
            HostName = [string]$instance['HostName']
            AssignedUserName = $assignedUser
        })
    }
    return $result.ToArray()
}

function Add-C1C2DirectoryChecks {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [Parameter(Mandatory)]$Manifest
    )
    $tableName = 'cfg_LinksPageDirectory'
    $expectedColumns = @('InstanceCode', 'ServerCode', 'CountryCode', 'CustomerCode', 'CustomerName', 'HostName', 'AssignedUserName')
    $schema = Get-C1C2VerifierDirectorySchema -Source $Source

    foreach ($entry in @($Manifest.catalogs)) {
        $code = [string]$entry.serverCode
        $db = Join-Path $Folder ([string]$entry.file)
        if (-not (Test-Path -LiteralPath $db -PathType Leaf)) { continue }
        $columnMap = & $script:C1C2CoreGetCatalogColumns -Sqlite3 $Sqlite3 -Db $db
        $hasTable = $columnMap.Contains($tableName)
        Add-Check 'instance-directory' ('{0}: cfg_LinksPageDirectory exists' -f $code) $hasTable
        if (-not $hasTable) { continue }

        $actualColumns = @($columnMap[$tableName])
        Add-Check 'instance-directory' ('{0}: directory has only the seven approved public columns' -f $code) (($actualColumns -join ',') -ceq ($expectedColumns -join ',')) (($actualColumns -join ','))
        if (($actualColumns -join ',') -cne ($expectedColumns -join ',')) { continue }

        $plan = [ordered]@{}
        $plan[$tableName] = $expectedColumns
        $read = Read-CatalogRows -Sqlite3 $Sqlite3 -Db $db -Plan $plan
        $actualRows = @()
        if ($read.Contains($tableName)) { $actualRows = @($read[$tableName]) }
        $expectedRows = @(Get-C1C2ExpectedDirectoryRows -Source $Source -CatalogServerCode $code)
        $cmp = Compare-TableRows -Table $tableName -Columns $schema.Columns -PrimaryKey @('InstanceCode') -ExpectedRows $expectedRows -CatalogRows $actualRows -RedactedIds @{} -Spec $null
        Add-Check 'instance-directory' ('{0}: directory exactly matches enabled remote same-country instances' -f $code) $cmp.Ok ('expected {0}, catalog {1}, missing {2}, extra {3}, different {4}, duplicate {5}' -f $cmp.Expected, $cmp.Catalog, $cmp.Missing, $cmp.Extra, $cmp.Different, $cmp.Duplicate)

        $manifestCount = $null
        if ($entry.PSObject.Properties['linksPageDirectoryCount']) { $manifestCount = [int]$entry.linksPageDirectoryCount }
        Add-Check 'instance-directory' ('{0}: manifest records the directory row count' -f $code) ($null -ne $manifestCount -and $manifestCount -eq $actualRows.Count) ('catalog {0}, manifest {1}' -f $actualRows.Count, $(if ($null -eq $manifestCount) { '<missing>' } else { $manifestCount }))

        $localInstances = @{}
        $generalCountries = @{}
        foreach ($instance in $Source.Rows['dbo.ManagedInstance']) {
            if ([string]$instance['ServerCode'] -ieq $code) {
                $localInstances[([string]$instance['InstanceCode']).ToLowerInvariant()] = $true
                $enabled = $instance.Contains('IsEnabled') -and $null -ne $instance['IsEnabled'] -and [int]$instance['IsEnabled'] -eq 1
                $general = $instance.Contains('LinksIncludeAllInstances') -and $null -ne $instance['LinksIncludeAllInstances'] -and [int]$instance['LinksIncludeAllInstances'] -eq 1
                if ($enabled -and $general) { $generalCountries[([string]$instance['CountryCode']).ToLowerInvariant()] = $true }
            }
        }
        $instanceIndex = [array]::IndexOf($expectedColumns, 'InstanceCode')
        $serverIndex = [array]::IndexOf($expectedColumns, 'ServerCode')
        $countryIndex = [array]::IndexOf($expectedColumns, 'CountryCode')
        $localLeak = 0; $sameServer = 0; $wrongCountry = 0
        foreach ($cells in $actualRows) {
            $instanceCode = ConvertFrom-TokenText $cells[$instanceIndex]
            $serverCode = ConvertFrom-TokenText $cells[$serverIndex]
            $countryCode = ConvertFrom-TokenText $cells[$countryIndex]
            if ($localInstances.ContainsKey($instanceCode.ToLowerInvariant())) { $localLeak++ }
            if ($serverCode -ieq $code) { $sameServer++ }
            if (-not $generalCountries.ContainsKey($countryCode.ToLowerInvariant())) { $wrongCountry++ }
        }
        Add-Check 'instance-directory' ('{0}: directory contains no local instance or own ServerCode' -f $code) ($localLeak -eq 0 -and $sameServer -eq 0) ('local instances {0}, own-server rows {1}' -f $localLeak, $sameServer)
        Add-Check 'instance-directory' ('{0}: every directory country is served by a local general page' -f $code) ($wrongCountry -eq 0) ('wrong-country rows: ' + $wrongCountry)
        if ($generalCountries.Count -eq 0) {
            Add-Check 'instance-directory' ('{0}: C2 machine without a general page has an empty directory' -f $code) ($actualRows.Count -eq 0) ('rows: ' + $actualRows.Count)
        }
    }
}

function Invoke-CatalogConversionTest {
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Sqlite3,
        [string[]]$ExtraNeedles = @()
    )
    if (-not $script:CarriedTables.Contains('cfg.LinksPageDirectory')) {
        return (& $script:C1C2CoreInvokeCatalogConversionTest @PSBoundParameters)
    }

    $directoryClass = $script:CarriedTables['cfg.LinksPageDirectory']
    [void]$script:CarriedTables.Remove('cfg.LinksPageDirectory')
    $script:C1C2HideDirectoryForCore = $true
    try {
        $legacy = & $script:C1C2CoreInvokeCatalogConversionTest @PSBoundParameters
    }
    finally {
        $script:C1C2HideDirectoryForCore = $false
        $script:CarriedTables['cfg.LinksPageDirectory'] = $directoryClass
    }
    if ($legacy.Catalogs -le 0 -or [string]::IsNullOrWhiteSpace([string]$legacy.Mode)) { return $legacy }

    $manifestPath = Join-Path $Folder 'conversion-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return $legacy }
    try {
        $manifest = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($manifestPath)) | ConvertFrom-Json
        Add-C1C2DirectoryChecks -Source $Source -Folder $Folder -Sqlite3 $Sqlite3 -Manifest $manifest
    }
    catch {
        Add-Check 'instance-directory' 'C1/C2 directory verification completed without an internal error' $false $_.Exception.Message
    }
    return (New-TestResult -Mode $legacy.Mode -Catalogs $legacy.Catalogs)
}

if ($script:C1C2VerifierShouldExecute) {
    $cli = $script:C1C2VerifierCli
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
