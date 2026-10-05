#requires -Version 7.0
<#
.SYNOPSIS
    Spike: pin Microsoft.Data.SqlClient for the conversion tools and test it on a Windows runner.

.DESCRIPTION
    Approved by the owner on 2026-10-05 (docs/migration/catalog-conversion-plan.md, section 5).
    Runs on a disposable GitHub-hosted Windows runner. It never needs credentials: it uses
    public NuGet metadata, and an optional connection with integrated security to a SQL
    Server that the runner image may carry.

    Steps (each recorded in report.json as PASS, FAIL, INFO or SKIPPED):
      1. resolve the version (latest stable on nuget.org unless -Version is given);
      2. download the .nupkg, compute SHA-256 and SHA-512, compare the SHA-512 with the
         packageHash published in the NuGet catalog;
      3. verify the package signature (dotnet nuget verify) and read licence and authors;
      4. publish a tiny framework-dependent project to collect the full dependency closure
         (managed DLLs and the native SNI library) and hash every file;
      5. download the pinned PowerShell 7.6.6 ZIP (hash from vendor/manifest.json, PR #10),
         load the client in it and read the assembly identity;
      6. probe a SQL Server on the runner and run one read-only query (informational).

    The script never stops at the first failure: it records the error and goes on, so the
    report always exists. The exit code is 1 when a required step (1 to 5) failed.
#>
[CmdletBinding()]
param(
    [string]$Version = '',
    [Parameter(Mandatory)][string]$OutputFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
$script:Steps = [System.Collections.Generic.List[object]]::new()
$script:Facts = [ordered]@{}
$script:RequiredFailed = $false

function Add-Step {
    param([string]$Name, [string]$Status, [string]$Details = '', [bool]$Required = $true)
    if ($Details.Length -gt 1800) { $Details = $Details.Substring(0, 1800) + ' ...' }
    $script:Steps.Add([ordered]@{ step = $Name; status = $Status; details = $Details })
    if ($Status -eq 'FAIL' -and $Required) { $script:RequiredFailed = $true }
    Write-Host ('[{0}] {1} {2}' -f $Status, $Name, $Details)
}

function Get-HashHex {
    param([string]$Path, [string]$Algorithm)
    return (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
}

$packageId = 'Microsoft.Data.SqlClient'
$idLower = $packageId.ToLowerInvariant()
$nupkg = $null
$publishDir = Join-Path $OutputFolder 'closure'

# 1. Version -----------------------------------------------------------------
try {
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $index = Invoke-RestMethod -Uri ('https://api.nuget.org/v3-flatcontainer/{0}/index.json' -f $idLower)
        $stable = @($index.versions | Where-Object { $_ -notmatch '-' } | Sort-Object { [version]($_ -replace '\+.*$', '') })
        if ($stable.Count -eq 0) { throw 'No stable version found.' }
        $Version = $stable[-1]
        $script:Facts['latestStableVersions'] = @($stable | Select-Object -Last 5)
    }
    $script:Facts['version'] = $Version
    Add-Step 'resolve version' 'PASS' $Version
}
catch { Add-Step 'resolve version' 'FAIL' $_.Exception.Message }

# 2. Download and hash -------------------------------------------------------
if ($script:Facts.Contains('version')) {
    try {
        $verLower = $Version.ToLowerInvariant()
        $nupkg = Join-Path $OutputFolder ('{0}.{1}.nupkg' -f $idLower, $verLower)
        $url = 'https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg' -f $idLower, $verLower
        Invoke-WebRequest -Uri $url -OutFile $nupkg
        $sha256 = Get-HashHex -Path $nupkg -Algorithm SHA256
        $sha512Bytes = [System.Security.Cryptography.SHA512]::HashData([System.IO.File]::ReadAllBytes($nupkg))
        $sha512B64 = [Convert]::ToBase64String($sha512Bytes)
        $script:Facts['nupkgUrl'] = $url
        $script:Facts['nupkgBytes'] = (Get-Item -LiteralPath $nupkg).Length
        $script:Facts['nupkgSha256'] = $sha256
        $script:Facts['nupkgSha512Base64'] = $sha512B64
        Add-Step 'download nupkg and hash' 'PASS' ('SHA-256 {0}' -f $sha256)

        $published = $null
        try {
            $leaf = Invoke-RestMethod -Uri ('https://api.nuget.org/v3/registration5-gz-semver2/{0}/{1}.json' -f $idLower, $verLower)
            $entry = Invoke-RestMethod -Uri $leaf.catalogEntry
            $published = [string]$entry.packageHash
            $script:Facts['catalogPackageHashAlgorithm'] = [string]$entry.packageHashAlgorithm
            $script:Facts['licenseExpression'] = [string]$entry.licenseExpression
            $script:Facts['authors'] = [string]$entry.authors
            $script:Facts['publishedUtc'] = [string]$entry.published
        }
        catch { Add-Step 'read NuGet catalog entry' 'FAIL' $_.Exception.Message }
        if ($published) {
            if ($published -ceq $sha512B64) { Add-Step 'SHA-512 equals the NuGet catalog packageHash' 'PASS' 'match' }
            else { Add-Step 'SHA-512 equals the NuGet catalog packageHash' 'FAIL' 'mismatch' }
        }
    }
    catch { Add-Step 'download nupkg and hash' 'FAIL' $_.Exception.Message }
}

# 3. Signature ----------------------------------------------------------------
if ($nupkg -and (Test-Path -LiteralPath $nupkg)) {
    try {
        $out = & dotnet nuget verify --all $nupkg 2>&1 | Out-String
        $code = $LASTEXITCODE
        $script:Facts['signatureVerifyExitCode'] = $code
        $signer = ([regex]::Matches($out, '(?im)^\s*Subject Name:\s*(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() } | Select-Object -First 2) -join ' | '
        $script:Facts['signatureSigner'] = $signer
        if ($code -eq 0) { Add-Step 'package signature (dotnet nuget verify)' 'PASS' ('signer: ' + $signer) }
        else { Add-Step 'package signature (dotnet nuget verify)' 'FAIL' ($out.Trim()) }
    }
    catch { Add-Step 'package signature (dotnet nuget verify)' 'FAIL' $_.Exception.Message }
}

# 4. Dependency closure ---------------------------------------------------------
if ($script:Facts.Contains('version')) {
    try {
        $proj = Join-Path $OutputFolder 'proj'
        New-Item -ItemType Directory -Path $proj -Force | Out-Null
        $csproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <SelfContained>false</SelfContained>
    <ImplicitUsings>disable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="$packageId" Version="$Version" />
  </ItemGroup>
</Project>
"@
        [System.IO.File]::WriteAllText((Join-Path $proj 'pin.csproj'), $csproj)
        [System.IO.File]::WriteAllText((Join-Path $proj 'Program.cs'), "public static class Program { public static void Main() { } }`n")
        $raw = Join-Path $OutputFolder 'publish-raw'
        $log = & dotnet publish (Join-Path $proj 'pin.csproj') -c Release -o $raw 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw ('dotnet publish failed: ' + $log) }
        New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
        $files = @(Get-ChildItem -LiteralPath $raw -File | Where-Object { $_.Name -notlike 'pin.*' -and $_.Extension -eq '.dll' })
        foreach ($f in $files) { Copy-Item -LiteralPath $f.FullName -Destination $publishDir }
        $closure = foreach ($f in (Get-ChildItem -LiteralPath $publishDir -File | Sort-Object Name)) {
            $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($f.FullName)
            [ordered]@{
                file           = $f.Name
                bytes          = $f.Length
                sha256         = (Get-HashHex -Path $f.FullName -Algorithm SHA256)
                fileVersion    = [string]$info.FileVersion
                productVersion = [string]$info.ProductVersion
            }
        }
        $script:Facts['closureFiles'] = @($closure)
        $script:Facts['closureFileCount'] = @($closure).Count
        $names = @($closure | ForEach-Object { $_.file })
        $hasClient = $names -contains 'Microsoft.Data.SqlClient.dll'
        $hasSni = $names -contains 'Microsoft.Data.SqlClient.SNI.dll'
        $script:Facts['hasClientDll'] = $hasClient
        $script:Facts['hasNativeSni'] = $hasSni
        if ($hasClient) { Add-Step 'collect dependency closure' 'PASS' ('{0} files; native SNI present: {1}' -f @($closure).Count, $hasSni) }
        else { Add-Step 'collect dependency closure' 'FAIL' 'Microsoft.Data.SqlClient.dll is not in the publish output.' }

        $zip = Join-Path $OutputFolder 'sqlclient-closure.zip'
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Compress-Archive -Path (Join-Path $publishDir '*') -DestinationPath $zip
        $script:Facts['closureZipSha256'] = Get-HashHex -Path $zip -Algorithm SHA256
        $script:Facts['closureZipBytes'] = (Get-Item -LiteralPath $zip).Length
    }
    catch { Add-Step 'collect dependency closure' 'FAIL' $_.Exception.Message }
}

# 5. Load in the pinned PowerShell ---------------------------------------------
$pwshExe = $null
try {
    $zipUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.zip'
    $expected = '02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860'   # vendor/manifest.json (PR #10)
    $psZip = Join-Path $OutputFolder 'pwsh-766.zip'
    Invoke-WebRequest -Uri $zipUrl -OutFile $psZip
    $actual = (Get-FileHash -LiteralPath $psZip -Algorithm SHA256).Hash
    if ($actual -ne $expected) { throw ('PowerShell ZIP SHA-256 mismatch: ' + $actual) }
    $psDir = Join-Path $OutputFolder 'pwsh-766'
    Expand-Archive -LiteralPath $psZip -DestinationPath $psDir -Force
    $pwshExe = Join-Path $psDir 'pwsh.exe'
    Add-Step 'pinned PowerShell 7.6.6 ZIP verified' 'PASS' 'SHA-256 matches vendor/manifest.json'
}
catch { Add-Step 'pinned PowerShell 7.6.6 ZIP verified' 'FAIL' $_.Exception.Message }

$loadTest = @'
param([string]$ClosureDir)
$ErrorActionPreference = 'Stop'
$dll = Join-Path $ClosureDir 'Microsoft.Data.SqlClient.dll'
Add-Type -Path $dll
$t = [Microsoft.Data.SqlClient.SqlConnection]
$b = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$b['Data Source'] = '.'
$b['Integrated Security'] = $true
$b['Application Intent'] = [Microsoft.Data.SqlClient.ApplicationIntent]::ReadOnly
$result = [ordered]@{
    psVersion      = $PSVersionTable.PSVersion.ToString()
    runtime        = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    assemblyVersion = $t.Assembly.GetName().Version.ToString()
    loadedFrom     = $t.Assembly.Location
    builderWorks   = ($b.ConnectionString.Length -gt 0)
}
$result | ConvertTo-Json -Compress
'@
$probeTest = @'
param([string]$ClosureDir, [string]$DataSource)
$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $ClosureDir 'Microsoft.Data.SqlClient.dll')
$b = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
$b['Data Source'] = $DataSource
$b['Integrated Security'] = $true
$b['Application Intent'] = [Microsoft.Data.SqlClient.ApplicationIntent]::ReadOnly
$b['Trust Server Certificate'] = $true
$b['Connect Timeout'] = 8
$c = [Microsoft.Data.SqlClient.SqlConnection]::new($b.ConnectionString)
try {
    $c.Open()
    $cmd = $c.CreateCommand()
    $cmd.CommandText = "SELECT CONVERT(nvarchar(128), SERVERPROPERTY('ProductVersion')) + '|' + CONVERT(nvarchar(128), SERVERPROPERTY('Collation'))"
    $cmd.ExecuteScalar()
}
finally { $c.Dispose() }
'@
if ($pwshExe -and (Test-Path -LiteralPath $publishDir)) {
    try {
        $loadFile = Join-Path $OutputFolder 'load-test.ps1'
        [System.IO.File]::WriteAllText($loadFile, $loadTest)
        $json = & $pwshExe -NoProfile -File $loadFile -ClosureDir $publishDir 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw $json }
        $obj = $json.Trim() | ConvertFrom-Json
        $script:Facts['loadTest'] = $obj
        if ($obj.builderWorks) { Add-Step 'load the client in the pinned PowerShell and build a connection string' 'PASS' ('assembly {0} on {1}' -f $obj.assemblyVersion, $obj.runtime) }
        else { Add-Step 'load the client in the pinned PowerShell and build a connection string' 'FAIL' $json }
    }
    catch { Add-Step 'load the client in the pinned PowerShell and build a connection string' 'FAIL' $_.Exception.Message }
}

# 6. SQL Server probe (informational) -------------------------------------------
try {
    $services = @(Get-Service -Name 'MSSQL*' -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType)
    $script:Facts['sqlServices'] = @($services | ForEach-Object { '{0}:{1}:{2}' -f $_.Name, $_.Status, $_.StartType })
    foreach ($svc in $services) {
        if ($svc.Name -like 'MSSQL$*' -and $svc.Status -ne 'Running') {
            try {
                if ($svc.StartType -eq 'Disabled') { Set-Service -Name $svc.Name -StartupType Manual }
                Start-Service -Name $svc.Name
            }
            catch { Add-Step ('start service ' + $svc.Name) 'INFO' $_.Exception.Message $false }
        }
    }
    Add-Step 'SQL Server services on the runner' 'INFO' (($script:Facts['sqlServices']) -join '; ') $false
}
catch { Add-Step 'SQL Server services on the runner' 'INFO' $_.Exception.Message $false }

$probeResults = [System.Collections.Generic.List[object]]::new()
if ($pwshExe -and (Test-Path -LiteralPath $publishDir)) {
    $probeFile = Join-Path $OutputFolder 'probe-test.ps1'
    [System.IO.File]::WriteAllText($probeFile, $probeTest)
    foreach ($source in @('.\SQLEXPRESS', '(localdb)\MSSQLLocalDB', '.', 'localhost,1433')) {
        try {
            $text = & $pwshExe -NoProfile -File $probeFile -ClosureDir $publishDir -DataSource $source 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw $text }
            $probeResults.Add([ordered]@{ dataSource = $source; ok = $true; result = $text.Trim() })
        }
        catch {
            $m = $_.Exception.Message
            if ($m.Length -gt 300) { $m = $m.Substring(0, 300) + ' ...' }
            $probeResults.Add([ordered]@{ dataSource = $source; ok = $false; result = $m })
        }
    }
    $script:Facts['sqlProbe'] = @($probeResults)
    $okCount = @($probeResults | Where-Object { $_.ok }).Count
    if ($okCount -gt 0) { Add-Step 'read-only query against a SQL Server on the runner' 'PASS' (($probeResults | Where-Object { $_.ok } | ForEach-Object { $_.dataSource + ' -> ' + $_.result }) -join '; ') $false }
    else { Add-Step 'read-only query against a SQL Server on the runner' 'INFO' 'No SQL Server answered; the SQL Server path stays [V].' $false }
}
else { Add-Step 'read-only query against a SQL Server on the runner' 'SKIPPED' 'client or PowerShell not available' $false }

# Report ---------------------------------------------------------------------------
$report = [ordered]@{
    contractVersion = '0.1-proposed'
    spike           = 'sqlclient-pin'
    runnerImage     = [string]$env:ImageVersion
    runnerOs        = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    dotnetSdks      = @((& dotnet --list-sdks 2>&1) | ForEach-Object { [string]$_ })
    generatedUtc    = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    requiredFailed  = $script:RequiredFailed
    facts           = $script:Facts
    steps           = $script:Steps.ToArray()
}
$json = ($report | ConvertTo-Json -Depth 8 -EscapeHandling EscapeNonAscii)
$json = ($json -replace "`r`n", "`n") + "`n"
[System.IO.File]::WriteAllBytes((Join-Path $OutputFolder 'report.json'), [System.Text.UTF8Encoding]::new($false).GetBytes($json))
Write-Host ('Report written. Required step failed: {0}' -f $script:RequiredFailed)
if ($script:RequiredFailed) { exit 1 }
