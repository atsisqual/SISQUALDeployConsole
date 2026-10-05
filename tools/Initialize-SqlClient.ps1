#requires -Version 7.0
<#
.SYNOPSIS
    Obtains the pinned Microsoft.Data.SqlClient closure into a folder and verifies every file.

.DESCRIPTION
    The tools Export-ManagementEngines.ps1 and Convert-ManagementDb.ps1 need the SQL client to
    read SQL Server. This helper restores the exact package version listed in
    vendor/sqlclient-pin.json with `dotnet publish` (the .NET SDK and access to nuget.org are
    needed on the machine that runs it), copies the managed and native DLLs to -OutputFolder
    and checks the SHA-256 of EVERY file against the pin. A missing, extra or different file
    stops the run and nothing is left in the output folder.

    Pass the output folder to the tools as -SqlClientPath.
    [PENDING] owner: other ways of delivering the files (a verified ZIP on a release, or a copy
    kept outside Git) are described in docs/phase1/sqlclient-pin.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputFolder,
    [string]$PinFile = (Join-Path $PSScriptRoot '..' 'vendor' 'sqlclient-pin.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath $PinFile -PathType Leaf)) { throw ('Pin file not found: {0}' -f $PinFile) }
$pin = Get-Content -LiteralPath $PinFile -Raw | ConvertFrom-Json
if ($pin.name -ne 'Microsoft.Data.SqlClient' -or [string]::IsNullOrWhiteSpace($pin.version) -or @($pin.files).Count -eq 0) {
    throw 'The pin file is not valid.'
}
if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'The .NET SDK (dotnet) is required to restore the pinned package.'
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('sqlclient-restore-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $csproj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>$($pin.targetFramework)</TargetFramework>
    <RuntimeIdentifier>$($pin.runtimeIdentifier)</RuntimeIdentifier>
    <SelfContained>false</SelfContained>
    <ImplicitUsings>disable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="$($pin.name)" Version="[$($pin.version)]" />
  </ItemGroup>
</Project>
"@
    [System.IO.File]::WriteAllText((Join-Path $work 'pin.csproj'), $csproj)
    [System.IO.File]::WriteAllText((Join-Path $work 'Program.cs'), "public static class Program { public static void Main() { } }`n")
    $raw = Join-Path $work 'publish'
    $log = & dotnet publish (Join-Path $work 'pin.csproj') -c Release -o $raw 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw ('dotnet publish failed: ' + $log) }

    $found = @(Get-ChildItem -LiteralPath $raw -File | Where-Object { $_.Name -notlike 'pin.*' -and $_.Extension -eq '.dll' })
    $pinned = @{}
    foreach ($entry in $pin.files) { $pinned[[string]$entry.file] = [string]$entry.sha256 }

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $pinned.Keys) {
        $f = $found | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($null -eq $f) { $problems.Add(('missing: {0}' -f $name)); continue }
        if ((Get-FileSha256 -Path $f.FullName) -ne $pinned[$name]) { $problems.Add(('hash mismatch: {0}' -f $name)) }
    }
    foreach ($f in $found) { if (-not $pinned.ContainsKey($f.Name)) { $problems.Add(('not in the pin: {0}' -f $f.Name)) } }
    if ($problems.Count -gt 0) { throw ('The restored files do not match the pin: ' + ($problems -join '; ')) }

    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    foreach ($f in $found) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $OutputFolder $f.Name) -Force }
    Write-Host ('{0} {1}: {2} files verified against the pin. Use -SqlClientPath {3}' -f $pin.name, $pin.version, $found.Count, $OutputFolder)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
