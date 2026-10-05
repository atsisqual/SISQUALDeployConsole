#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProviderRoot,

    [Parameter(Mandatory = $true)]
    [string]$SqliteCli,

    [Parameter(Mandatory = $true)]
    [string]$ReportPath,

    [string]$ExpectedProviderVersion = '10.0.12',
    [string]$ExpectedPowerShellVersion = '7.6.6'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$started = [DateTime]::UtcNow
$runId = [guid]::NewGuid().ToString('N')
$tempRoot = Join-Path $env:TEMP ('SISQUAL-Phase1B-Sqlite-' + $runId)
$checks = [System.Collections.Generic.List[object]]::new()
$fatal = $null

function Add-Check {
    param(
        [string]$Id,
        [ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
        [string]$Message,
        $Data = $null
    )

    $checks.Add([pscustomobject][ordered]@{
        id = $Id
        status = $Status
        message = $Message
        data = $Data
    })
}

function Find-OneFile {
    param([string]$Root, [string]$Name)

    $items = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Name -ErrorAction Stop)
    if ($items.Count -ne 1) {
        throw "Expected exactly one $Name below $Root; found $($items.Count)."
    }
    return $items[0].FullName
}

function Open-ReadOnlyConnection {
    param([string]$DatabasePath)

    $connectionString = 'Data Source={0};Mode=ReadOnly;Cache=Private' -f $DatabasePath
    $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($connectionString)
    $connection.Open()
    return $connection
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    $psVersion = $PSVersionTable.PSVersion.ToString()
    Add-Check 'HOST_POWERSHELL' $(if ($psVersion -eq $ExpectedPowerShellVersion) { 'PASS' } else { 'FAIL' }) `
        'Probe runs in the pinned portable PowerShell version.' `
        ([ordered]@{ expected = $ExpectedPowerShellVersion; actual = $psVersion; psHome = $PSHOME })

    if (-not (Test-Path -LiteralPath $ProviderRoot -PathType Container)) {
        throw "ProviderRoot not found: $ProviderRoot"
    }
    if (-not (Test-Path -LiteralPath $SqliteCli -PathType Leaf)) {
        throw "sqlite3 CLI not found: $SqliteCli"
    }

    $managedNames = @(
        'SQLitePCLRaw.core.dll',
        'SQLitePCLRaw.provider.e_sqlite3.dll',
        'SQLitePCLRaw.batteries_v2.dll',
        'Microsoft.Data.Sqlite.dll'
    )

    $managed = [ordered]@{}
    foreach ($name in $managedNames) {
        $managed[$name] = Find-OneFile -Root $ProviderRoot -Name $name
    }
    $native = Find-OneFile -Root $ProviderRoot -Name 'e_sqlite3.dll'

    Add-Check 'PROVIDER_PAYLOAD' 'PASS' 'Required managed and native provider files are present.' `
        ([ordered]@{ managed = @($managed.Keys); native = [IO.Path]::GetFileName($native) })

    $nativeDir = Split-Path -Parent $native
    $env:PATH = $nativeDir + [IO.Path]::PathSeparator + $env:PATH

    foreach ($name in $managedNames) {
        Add-Type -Path $managed[$name] -ErrorAction Stop
    }
    [SQLitePCL.Batteries_V2]::Init()

    $providerFile = Get-Item -LiteralPath $managed['Microsoft.Data.Sqlite.dll']
    $providerVersion = $providerFile.VersionInfo.ProductVersion
    $providerVersionMatch = $providerVersion -like ($ExpectedProviderVersion + '*')
    Add-Check 'PROVIDER_LOAD' $(if ($providerVersionMatch) { 'PASS' } else { 'FAIL' }) `
        'Microsoft.Data.Sqlite loads directly in PowerShell without installation.' `
        ([ordered]@{
            expected = $ExpectedProviderVersion
            productVersion = $providerVersion
            assembly = [Microsoft.Data.Sqlite.SqliteConnection].Assembly.FullName
            location = [Microsoft.Data.Sqlite.SqliteConnection].Assembly.Location
        })

    $dbDir = Join-Path $tempRoot 'catalog with spaces'
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    $dbPath = Join-Path $dbDir 'catalog test.db'

    $sql = @"
CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE sample(id INTEGER PRIMARY KEY, code TEXT NOT NULL, amount INTEGER NOT NULL);
INSERT INTO metadata(key,value) VALUES('schemaVersion','1');
WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10000)
INSERT INTO sample(id,code,amount) SELECT x, printf('C%05d',x), x*10 FROM n;
"@
    $cliOutput = & $SqliteCli $dbPath $sql 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sqlite3 fixture creation failed: $($cliOutput -join ' ')"
    }

    $fixtureHashBefore = (Get-FileHash -LiteralPath $dbPath -Algorithm SHA256).Hash
    Add-Check 'FIXTURE_CREATED' 'PASS' 'Fixture catalog was created by the pinned sqlite3 CLI.' `
        ([ordered]@{ bytes = (Get-Item $dbPath).Length; sha256 = $fixtureHashBefore })

    $connection = Open-ReadOnlyConnection -DatabasePath $dbPath
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT COUNT(*) FROM sample;'
        $count = [int64]$command.ExecuteScalar()
        $command.Dispose()

        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT sqlite_version();'
        $nativeVersion = [string]$command.ExecuteScalar()
        $command.Dispose()

        $command = $connection.CreateCommand()
        $command.CommandText = 'SELECT code FROM sample WHERE id = $id;'
        $parameter = $command.CreateParameter()
        $parameter.ParameterName = '$id'
        $parameter.Value = 42
        [void]$command.Parameters.Add($parameter)
        $parameterizedValue = [string]$command.ExecuteScalar()
        $command.Dispose()

        $command = $connection.CreateCommand()
        $command.CommandText = 'PRAGMA integrity_check;'
        $integrity = [string]$command.ExecuteScalar()
        $command.Dispose()
    }
    finally {
        $connection.Dispose()
    }

    $readPass = ($count -eq 10000 -and $parameterizedValue -eq 'C00042' -and $integrity -eq 'ok')
    Add-Check 'READ_ONLY_READS' $(if ($readPass) { 'PASS' } else { 'FAIL' }) `
        'Read-only connection supports catalog reads, parameters and integrity_check.' `
        ([ordered]@{ rows = $count; parameterizedValue = $parameterizedValue; integrity = $integrity; sqliteVersion = $nativeVersion })

    $writeRejected = $false
    $writeErrorCode = $null
    $connection = Open-ReadOnlyConnection -DatabasePath $dbPath
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = "INSERT INTO metadata(key,value) VALUES('forbidden','write');"
        try {
            [void]$command.ExecuteNonQuery()
        }
        catch {
            $writeRejected = $true
            if ($_.Exception.PSObject.Properties.Name -contains 'SqliteErrorCode') {
                $writeErrorCode = $_.Exception.SqliteErrorCode
            }
        }
        finally {
            $command.Dispose()
        }
    }
    finally {
        $connection.Dispose()
    }

    Add-Check 'WRITE_REJECTED' $(if ($writeRejected) { 'PASS' } else { 'FAIL' }) `
        'A write through Mode=ReadOnly must fail.' `
        ([ordered]@{ rejected = $writeRejected; sqliteErrorCode = $writeErrorCode })

    $missingPath = Join-Path $dbDir 'must-not-exist.db'
    $missingRejected = $false
    try {
        $missingConnection = Open-ReadOnlyConnection -DatabasePath $missingPath
        $missingConnection.Dispose()
    }
    catch {
        $missingRejected = $true
    }
    $missingPass = $missingRejected -and -not (Test-Path -LiteralPath $missingPath)
    Add-Check 'MISSING_FILE_REJECTED' $(if ($missingPass) { 'PASS' } else { 'FAIL' }) `
        'Read-only mode must not create a missing database.' `
        ([ordered]@{ rejected = $missingRejected; fileCreated = (Test-Path -LiteralPath $missingPath) })

    $connections = [System.Collections.Generic.List[object]]::new()
    $parallelReadPass = $true
    try {
        for ($i = 0; $i -lt 20; $i++) {
            $c = Open-ReadOnlyConnection -DatabasePath $dbPath
            $connections.Add($c)
            $cmd = $c.CreateCommand()
            $cmd.CommandText = 'SELECT value FROM metadata WHERE key = $key;'
            $p = $cmd.CreateParameter()
            $p.ParameterName = '$key'
            $p.Value = 'schemaVersion'
            [void]$cmd.Parameters.Add($p)
            if ([string]$cmd.ExecuteScalar() -ne '1') {
                $parallelReadPass = $false
            }
            $cmd.Dispose()
        }
    }
    catch {
        $parallelReadPass = $false
    }
    finally {
        foreach ($c in $connections) {
            $c.Dispose()
        }
    }
    Add-Check 'MULTIPLE_READ_CONNECTIONS' $(if ($parallelReadPass) { 'PASS' } else { 'FAIL' }) `
        'Twenty simultaneous read-only connections can open and query the same catalog.'

    $fixtureHashAfter = (Get-FileHash -LiteralPath $dbPath -Algorithm SHA256).Hash
    $sidecars = @(Get-ChildItem -LiteralPath $dbDir -File | Where-Object { $_.Name -ne (Split-Path -Leaf $dbPath) })
    $sidecarNames = @($sidecars | ForEach-Object { $_.Name })
    $noMutation = ($fixtureHashBefore -eq $fixtureHashAfter -and $sidecars.Count -eq 0)
    Add-Check 'NO_CATALOG_MUTATION' $(if ($noMutation) { 'PASS' } else { 'FAIL' }) `
        'Read-only use leaves the catalog bytes unchanged and creates no sidecar files.' `
        ([ordered]@{ before = $fixtureHashBefore; after = $fixtureHashAfter; sidecars = $sidecarNames })
}
catch {
    $fatal = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
    Add-Check 'FATAL' 'FAIL' 'The spike stopped on an unexpected error.' ([ordered]@{ error = $fatal })
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $failures = @($checks | Where-Object { $_.status -eq 'FAIL' })
    $completed = [DateTime]::UtcNow
    $report = [pscustomobject][ordered]@{
        phase = '1B'
        probe = 'sqlite-managed-provider'
        status = '[PROPOSED]'
        candidate = 'Microsoft.Data.Sqlite'
        candidateVersion = $ExpectedProviderVersion
        overall = $(if ($failures.Count -eq 0 -and $null -eq $fatal) { 'PASS' } else { 'FAIL' })
        machine = $env:COMPUTERNAME
        os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        powerShell = $PSVersionTable.PSVersion.ToString()
        startedAtUtc = $started.ToString('o')
        completedAtUtc = $completed.ToString('o')
        durationSeconds = [math]::Round(($completed - $started).TotalSeconds, 3)
        checks = @($checks)
        fatalError = $fatal
    }

    $reportDir = Split-Path -Parent $ReportPath
    if ($reportDir -and -not (Test-Path -LiteralPath $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
    $report | ConvertTo-Json -Depth 12

    if ($report.overall -ne 'PASS') {
        exit 1
    }
}
