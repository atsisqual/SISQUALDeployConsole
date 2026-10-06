#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite3 = $env:SQLITE3_PATH
if ([string]::IsNullOrWhiteSpace($sqlite3)) {
    $found = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($found) { $sqlite3 = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($sqlite3) -or -not (Test-Path -LiteralPath $sqlite3 -PathType Leaf)) {
    Write-Host 'sqlite3 was not found. Set SQLITE3_PATH to the pinned sqlite3 executable.'
    exit 2
}

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Test-CatalogConversion.ps1')).Path
. $toolPath -SyncFile 'unused' -CatalogFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failures = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0} {1}' -f $Name, $Detail) }
}
function New-Column {
    param([string]$Name, [string]$Type, [int]$Length = 0, [bool]$Nullable = $false)
    return [pscustomobject]@{ Name = $Name; Type = $Type; Length = $Length; Precision = 0; Scale = 0; Identity = $false; Nullable = $Nullable }
}
function New-List { return ,([System.Collections.Generic.List[object]]::new()) }

# Narrow fixture: two source tables plus the derived C1/C2 table. This keeps the test focused
# while still exercising catalog writing, manifest counts and the independent verifier overlay.
$script:CarriedTables = [ordered]@{
    'dbo.ManagedServer' = 'S'
    'dbo.ManagedInstance' = 'I'
    'cfg.LinksPageDirectory' = 'D'
}

$serverSchema = [pscustomobject]@{
    Table = 'dbo.ManagedServer'
    Columns = @(
        (New-Column 'ServerCode' 'varchar' 30),
        (New-Column 'MachineName' 'sysname' 128),
        (New-Column 'IsEnabled' 'bit')
    )
    PrimaryKey = @('ServerCode')
}
$instanceSchema = [pscustomobject]@{
    Table = 'dbo.ManagedInstance'
    Columns = @(
        (New-Column 'InstanceCode' 'varchar' 30),
        (New-Column 'ServerCode' 'varchar' 30),
        (New-Column 'CountryCode' 'char' 2),
        (New-Column 'CustomerCode' 'int' 0 $true),
        (New-Column 'CustomerName' 'nvarchar' 100 $true),
        (New-Column 'HostName' 'sysname' 128),
        (New-Column 'IsEnabled' 'bit'),
        (New-Column 'LinksIncludeAllInstances' 'bit'),
        (New-Column 'LinksAssignedUserName' 'nvarchar' 150 $true)
    )
    PrimaryKey = @('InstanceCode')
}
$schema = @{
    'dbo.ManagedServer' = $serverSchema
    'dbo.ManagedInstance' = $instanceSchema
}
$schema['cfg.LinksPageDirectory'] = Get-LinksPageDirectorySchema -ManagedInstanceSchema $instanceSchema

$servers = New-List
foreach ($row in @(
    [ordered]@{ ServerCode = 'SRV_A'; MachineName = 'HOST-A'; IsEnabled = 1 },
    [ordered]@{ ServerCode = 'SRV_B'; MachineName = 'HOST-B'; IsEnabled = 1 },
    [ordered]@{ ServerCode = 'SRV_C'; MachineName = 'HOST-C'; IsEnabled = 0 },
    [ordered]@{ ServerCode = 'SRV_D'; MachineName = 'HOST-D'; IsEnabled = 1 }
)) { $servers.Add($row) }

$instances = New-List
foreach ($row in @(
    [ordered]@{ InstanceCode = 'A_MAIN'; ServerCode = 'SRV_A'; CountryCode = 'PT'; CustomerCode = 1001; CustomerName = 'Alpha'; HostName = 'a-main.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 1; LinksAssignedUserName = 'Alpha User' },
    [ordered]@{ InstanceCode = 'A_LOCAL'; ServerCode = 'SRV_A'; CountryCode = 'PT'; CustomerCode = 1002; CustomerName = 'Alpha Local'; HostName = 'a-local.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 0; LinksAssignedUserName = $null },
    [ordered]@{ InstanceCode = 'B_PT'; ServerCode = 'SRV_B'; CountryCode = 'PT'; CustomerCode = $null; CustomerName = $null; HostName = 'b-pt.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 0; LinksAssignedUserName = 'Public Operator' },
    [ordered]@{ InstanceCode = 'B_ES'; ServerCode = 'SRV_B'; CountryCode = 'ES'; CustomerCode = 2002; CustomerName = 'Beta ES'; HostName = 'b-es.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 0; LinksAssignedUserName = $null },
    [ordered]@{ InstanceCode = 'B_OFF'; ServerCode = 'SRV_B'; CountryCode = 'PT'; CustomerCode = 2003; CustomerName = 'Beta Off'; HostName = 'b-off.example.test'; IsEnabled = 0; LinksIncludeAllInstances = 0; LinksAssignedUserName = $null },
    [ordered]@{ InstanceCode = 'C_PT'; ServerCode = 'SRV_C'; CountryCode = 'PT'; CustomerCode = 3001; CustomerName = 'Disabled Server'; HostName = 'c-pt.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 0; LinksAssignedUserName = $null },
    [ordered]@{ InstanceCode = 'D_MAIN'; ServerCode = 'SRV_D'; CountryCode = 'PT'; CustomerCode = 4001; CustomerName = 'Delta'; HostName = 'd-main.example.test'; IsEnabled = 1; LinksIncludeAllInstances = 1; LinksAssignedUserName = 'Delta User' }
)) { $instances.Add($row) }

$source = [pscustomobject]@{
    Schema = $schema
    Rows = @{
        'dbo.ManagedServer' = $servers
        'dbo.ManagedInstance' = $instances
        'cfg.LinksPageDirectory' = (New-List)
    }
}

Assert-That 'C1/C2 overlay bumps only the cut-rule version' ($script:SchemaVersion -eq 1 -and $script:CutRuleVersion -eq 2 -and $script:ToolVersion -ceq '0.3.1')
$dirCols = @($schema['cfg.LinksPageDirectory'].Columns | ForEach-Object { $_.Name })
Assert-That 'directory schema has the seven approved public columns' (($dirCols -join ',') -ceq 'InstanceCode,ServerCode,CountryCode,CustomerCode,CustomerName,HostName,AssignedUserName')
Assert-That 'directory preserves nullable CustomerCode and CustomerName' (($schema['cfg.LinksPageDirectory'].Columns | Where-Object Name -eq 'CustomerCode').Nullable -and ($schema['cfg.LinksPageDirectory'].Columns | Where-Object Name -eq 'CustomerName').Nullable)

$aRows = @(Get-LinksPageDirectoryRows -Source $source -CatalogServerCode 'SRV_A')
Assert-That 'SRV_A general PT page sees two enabled remote PT instances' ($aRows.Count -eq 2 -and @($aRows.InstanceCode | Sort-Object) -join ',' -ceq 'B_PT,D_MAIN')
$bpt = @($aRows | Where-Object { $_['InstanceCode'] -ceq 'B_PT' })[0]
Assert-That 'C1 AssignedUserName is carried byte-exact' ([string]$bpt['AssignedUserName'] -ceq 'Public Operator')
Assert-That 'nullable customer fields are preserved as NULL' ($null -eq $bpt['CustomerCode'] -and $null -eq $bpt['CustomerName'])
Assert-That 'disabled instances and disabled-server instances are excluded' (@($aRows | Where-Object { $_['InstanceCode'] -in @('B_OFF', 'C_PT') }).Count -eq 0)
Assert-That 'local instances never enter their own directory' (@($aRows | Where-Object { [string]$_['ServerCode'] -ceq 'SRV_A' }).Count -eq 0)
$bRows = @(Get-LinksPageDirectoryRows -Source $source -CatalogServerCode 'SRV_B')
Assert-That 'C2 machine without a general page has an empty directory' ($bRows.Count -eq 0)
$cRows = @(Get-LinksPageDirectoryRows -Source $source -CatalogServerCode 'SRV_C')
Assert-That 'disabled machine has an empty directory' ($cRows.Count -eq 0)
$dRows = @(Get-LinksPageDirectoryRows -Source $source -CatalogServerCode 'SRV_D')
Assert-That 'same-country matching is cross-machine and excludes disabled targets' ($dRows.Count -eq 3 -and @($dRows.InstanceCode | Sort-Object) -join ',' -ceq 'A_LOCAL,A_MAIN,B_PT')

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('links-directory-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $newMachineOut = Join-Path $work 'new-machine'
    $newMachine = Invoke-NewMachineConversion -Source $source -SourceInfo @{ kind = 'test' } -Folder $newMachineOut -Sqlite3 $sqlite3 -Code 'SRV_NEW' -Machine 'HOST-NEW' -Services 'C:\Services' -BackupRoot 'C:\Backups' -SourceRef 'c1-c2-new-machine' 6>$null
    $newMachineManifest = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($newMachine.Manifest)) | ConvertFrom-Json
    $newMachineEntry = @($newMachineManifest.catalogs)[0]
    $newMachineDirectoryCount = [int](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $newMachine.Catalog, 'SELECT count(*) FROM cfg_LinksPageDirectory;')).Trim()
    Assert-That 'new-machine C2 directory is empty and recorded as zero' ($newMachineDirectoryCount -eq 0 -and [int]$newMachineEntry.linksPageDirectoryCount -eq 0)
    Assert-That 'new-machine C2 does not report the expected empty directory as a missing policy' (@($newMachineEntry.findings | Where-Object { $_ -like 'cfg_LinksPageDirectory is empty*' }).Count -eq 0)

    $result = Invoke-CutConversion -Source $source -SourceInfo @{ kind = 'test' } -Folder $work -Sqlite3 $sqlite3 -Codes @('ALL') -SourceRef 'c1-c2-test' 6>$null
    Assert-That 'cut conversion builds all four catalogs' (@($result.Catalogs).Count -eq 4)

    $counts = @{}
    foreach ($code in @('SRV_A', 'SRV_B', 'SRV_C', 'SRV_D')) {
        $db = Join-Path $work ('catalog-{0}.db' -f $code)
        $counts[$code] = [int](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $db, 'SELECT count(*) FROM cfg_LinksPageDirectory;')).Trim()
    }
    Assert-That 'catalog row counts follow C1/C2 selection' ($counts['SRV_A'] -eq 2 -and $counts['SRV_B'] -eq 0 -and $counts['SRV_C'] -eq 0 -and $counts['SRV_D'] -eq 3)

    $aDb = Join-Path $work 'catalog-SRV_A.db'
    $assigned = (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $aDb, "SELECT AssignedUserName FROM cfg_LinksPageDirectory WHERE InstanceCode='B_PT';")).Trim()
    Assert-That 'written catalog carries the public assigned user name' ($assigned -ceq 'Public Operator')
    $nulls = (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $aDb, "SELECT (CustomerCode IS NULL) || '|' || (CustomerName IS NULL) FROM cfg_LinksPageDirectory WHERE InstanceCode='B_PT';")).Trim()
    Assert-That 'written catalog keeps nullable customer fields NULL' ($nulls -ceq '1|1')

    $manifest = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $work 'conversion-manifest.json'))) | ConvertFrom-Json
    $manifestCounts = @{}
    foreach ($entry in @($manifest.catalogs)) { $manifestCounts[[string]$entry.serverCode] = [int]$entry.linksPageDirectoryCount }
    Assert-That 'manifest records directory count per catalog' ($manifestCounts['SRV_A'] -eq 2 -and $manifestCounts['SRV_B'] -eq 0 -and $manifestCounts['SRV_C'] -eq 0 -and $manifestCounts['SRV_D'] -eq 3)

    $verified = Invoke-CatalogConversionTest -Source $source -Folder $work -Sqlite3 $sqlite3 6>$null
    $directoryChecks = @($verified.Checks | Where-Object { $_.group -eq 'instance-directory' })
    Assert-That 'independent verifier passes the intact populated directories' ($verified.Failed -eq 0 -and $directoryChecks.Count -gt 0 -and @($directoryChecks | Where-Object { -not $_.ok }).Count -eq 0)

    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $work 'catalog-SRV_A.db'), "UPDATE cfg_LinksPageDirectory SET HostName='tampered.example.test' WHERE InstanceCode='B_PT';"))
    $tampered = Invoke-CatalogConversionTest -Source $source -Folder $work -Sqlite3 $sqlite3 6>$null
    Assert-That 'verifier detects a directory value mutation' (@($tampered.Checks | Where-Object { $_.group -eq 'instance-directory' -and -not $_.ok }).Count -gt 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('Links directory tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
exit 0