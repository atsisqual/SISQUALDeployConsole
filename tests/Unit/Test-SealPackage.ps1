#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for tools/Seal-Package.ps1 (no network, no SQL Server, no credential tool).

.DESCRIPTION
    Builds small synthetic packages in a temporary folder. The signer and the verifier used here are
    TEST DOUBLES: a throw-away ECDSA key created by this test and held only in a temporary file. The
    tool itself contains no signature algorithm; the real signer comes with the credential tool
    (step B6) once the owner approves the algorithm. Marker values stand in for secrets.
    Needs the sqlite3 executable named by SQLITE3_PATH. Exits 1 on failure, 2 when sqlite3 is missing.
#>
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

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Seal-Package.ps1')).Path
$convertPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1')).Path
. $toolPath -PackageFolder 'unused' -Sqlite3Path 'unused'

$script:Failures = 0
$script:Passed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}
function Get-Folder-Snapshot {
    param([string]$Folder)
    return ((@(Get-ChildItem -LiteralPath $Folder -Recurse -File -Force | Sort-Object FullName | ForEach-Object { '{0}:{1}' -f $_.FullName.Substring($Folder.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join '|'))
}
function Invoke-Sql { param([string]$Db, [string]$Sql) return (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Db, $Sql)).Trim() }

$marker = 'Zq8Lm2' + 'MARKERS' + '41'
$eAcute = [string][char]0x00E9

# --- test doubles: signer and verifier -----------------------------------------------------------
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('seal-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$tools = Join-Path $work 'doubles'
New-Item -ItemType Directory -Path $tools | Out-Null
$ecdsa = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256'))
$privFile = Join-Path $tools 'test-private.b64'
$pubFile = Join-Path $tools 'test-public.b64'
[System.IO.File]::WriteAllText($privFile, [Convert]::ToBase64String($ecdsa.ExportPkcs8PrivateKey()))
[System.IO.File]::WriteAllText($pubFile, [Convert]::ToBase64String($ecdsa.ExportSubjectPublicKeyInfo()))
$signerPath = Join-Path $tools 'test-signer.ps1'
$verifierPath = Join-Path $tools 'test-verifier.ps1'
$badSignerPath = Join-Path $tools 'bad-signer.ps1'
$failSignerPath = Join-Path $tools 'fail-signer.ps1'
$signerText = @"
param([string]`$InputFile, [string]`$OutputFile)
`$k = [System.Security.Cryptography.ECDsa]::Create()
`$k.ImportPkcs8PrivateKey([Convert]::FromBase64String([System.IO.File]::ReadAllText('$($privFile.Replace("'", "''"))')), [ref]`$null)
`$sig = `$k.SignData([System.IO.File]::ReadAllBytes(`$InputFile), [System.Security.Cryptography.HashAlgorithmName]::SHA256)
`$id = ([BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData(`$k.ExportSubjectPublicKeyInfo())) -replace '-', '').ToLowerInvariant()
[System.IO.File]::WriteAllText(`$OutputFile, (@{ issuerKeyId = `$id; algorithm = 'TEST-DOUBLE-ECDSA'; value = [Convert]::ToBase64String(`$sig) } | ConvertTo-Json -Compress))
"@
[System.IO.File]::WriteAllText($signerPath, $signerText)
$verifierText = @"
param([string]`$InputFile, [string]`$SignatureFile)
`$k = [System.Security.Cryptography.ECDsa]::Create()
`$k.ImportSubjectPublicKeyInfo([Convert]::FromBase64String([System.IO.File]::ReadAllText('$($pubFile.Replace("'", "''"))')), [ref]`$null)
`$s = [System.IO.File]::ReadAllText(`$SignatureFile) | ConvertFrom-Json
if (`$k.VerifyData([System.IO.File]::ReadAllBytes(`$InputFile), [Convert]::FromBase64String(`$s.value), [System.Security.Cryptography.HashAlgorithmName]::SHA256)) { exit 0 } else { exit 1 }
"@
[System.IO.File]::WriteAllText($verifierPath, $verifierText)
$badSignerText = @'
param([string]$InputFile, [string]$OutputFile)
[System.IO.File]::WriteAllText($OutputFile, '{"issuerKeyId":"NOT-HEX","algorithm":"X","value":"!!"}')
'@
[System.IO.File]::WriteAllText($badSignerPath, $badSignerText)
[System.IO.File]::WriteAllText($failSignerPath, "param([string]`$InputFile, [string]`$OutputFile)`nexit 3`n")

# --- helpers to build catalogs and packages --------------------------------------------------------
function New-TestCatalog {
    param([string]$Path, [string]$Code = 'SRV_A', [int]$UserVersion = 1, [int]$SchemaVersion = 1, [string]$ExtraSql = '')
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
    $sql = @"
CREATE TABLE catalog_meta (meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1), schema_version INTEGER NOT NULL, server_code TEXT NOT NULL, source_kind TEXT NOT NULL, source_reference TEXT NOT NULL, built_at_utc TEXT NOT NULL, cut_rule_version INTEGER NOT NULL) STRICT;
INSERT INTO catalog_meta VALUES (1, $SchemaVersion, '$Code', 'conversion-tool', 'test', '2026-01-01T00:00:00Z', 1);
CREATE TABLE cfg_ConfigRule (RuleCode TEXT NOT NULL PRIMARY KEY, ExpectedTemplate TEXT NOT NULL) STRICT;
INSERT INTO cfg_ConfigRule VALUES ('R1', 'a plain template value');
INSERT INTO cfg_ConfigRule VALUES ('R2', 'Server={ServerName};Integrated Security=SSPI;');
CREATE TABLE dbo_ManagedServer (ServerCode TEXT NOT NULL PRIMARY KEY, MachineName TEXT NOT NULL) STRICT;
INSERT INTO dbo_ManagedServer VALUES ('$Code', 'HOST-A');
$ExtraSql
PRAGMA user_version = $UserVersion;
"@
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Path, $sql))
}
function New-TestPackage {
    param([string]$Dir, [string]$Code = 'SRV_A')
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    New-TestCatalog -Path (Join-Path $Dir "catalog/catalog-$Code.db") -Code $Code
    New-Item -ItemType Directory -Path (Join-Path $Dir 'engines') -Force | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $Dir 'engines/Invoke-A.ps1'), [System.Text.UTF8Encoding]::new($false).GetBytes("# engine`r`nWrite-Host 'accent $eAcute'`r`n"))
    New-Item -ItemType Directory -Path (Join-Path $Dir 'ui') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Dir 'ui/index.html'), "<html></html>`n")
    [System.IO.File]::WriteAllText((Join-Path $Dir 'Start.cmd'), "@echo off`r`n")
}
function New-ConversionManifest {
    param([string]$Dir, [string]$Code = 'SRV_A', [string]$Path)
    $hash = (Get-FileHash -LiteralPath (Join-Path $Dir "catalog/catalog-$Code.db") -Algorithm SHA256).Hash.ToLowerInvariant()
    $json = @{ convertedAtUtc = '2026-10-05T12:00:00Z'; catalogs = @(@{ serverCode = $Code; file = "catalog-$Code.db"; sha256 = $hash }) } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($Path, $json)
    return $Path
}
function Invoke-TestSeal {
    param(
        [string]$Folder, [string]$Signer = $signerPath, [bool]$AllowUnsigned = $false, [string]$Version = '', [string]$Conv = '',
        [string]$Forced = '', [string]$BaselineDb = '', [string]$NoteText = '', [string]$LogPath = '', [bool]$Confirmed = $true, [bool]$Preview = $false
    )
    $r = @(Invoke-Seal -Folder $Folder -Sqlite3 $sqlite3 -Signer $Signer -AllowUnsigned $AllowUnsigned -Version $Version -CatalogRel '' -ConversionManifestPath $Conv -ForcedOrigin $Forced -BaselineDb $BaselineDb -NoteText $NoteText -LogPath $LogPath -Confirmed $Confirmed -Preview $Preview)
    return $r[$r.Count - 1]
}
function Get-Verification { param([string]$Dir) return (Invoke-PackageVerification -Folder $Dir -Sqlite3 $sqlite3 -Verifier $verifierPath) }

try {
    # 1. Canonical form -----------------------------------------------------------------------------------
    $sample = [ordered]@{ b = 1; a = 'x"y\z'; c = @([ordered]@{ z = 1; y = ('caf' + $eAcute) }); d = @() }
    Assert-That 'canonical form: keys sorted, no spaces, escapes, non-ASCII as \u00e9, arrays kept' ((ConvertTo-CanonicalJson $sample) -ceq '{"a":"x\"y\\z","b":1,"c":[{"y":"caf\u00e9","z":1}],"d":[]}')
    Assert-That 'canonical form: control characters are escaped' ((ConvertTo-CanonicalJson ("a`nb`tc" + [char]1)) -ceq '"a\nb\tc\u0001"')
    $cm = [pscustomobject]@{ z = 2; a = [pscustomobject]@{ k = 'v' }; signature = [pscustomobject]@{ value = 'x' } }
    Assert-That 'canonical bytes leave out the signature and accept parsed JSON objects' (([System.Text.Encoding]::ASCII.GetString((Get-CanonicalManifestBytes -Manifest $cm))) -ceq '{"a":{"k":"v"},"z":2}')

    # 2. First seal -----------------------------------------------------------------------------------------
    $pkg = Join-Path $work 'pkg'
    New-TestPackage -Dir $pkg
    $conv = New-ConversionManifest -Dir $pkg -Path (Join-Path $work 'conversion-manifest.json')
    $catalogBefore = (Get-FileHash -LiteralPath (Join-Path $pkg 'catalog/catalog-SRV_A.db') -Algorithm SHA256).Hash
    $r1 = Invoke-TestSeal -Folder $pkg -Version '1.2.3' -Conv $conv
    $manifestPath = Join-Path $pkg 'package-manifest.json'
    Assert-That 'first seal: sealed, manifest and seal log written' ($r1.Sealed -and (Test-Path $manifestPath) -and (Test-Path ($pkg + '.seal.log')))
    $m1 = Read-ManifestFile -Path $manifestPath
    Assert-That 'first seal: the manifest is valid against the structure rules' (@(Test-ManifestStructure -Manifest $m1).Count -eq 0)
    $listed = @($m1.files)
    $paths = @($listed | ForEach-Object { $_.path })
    Assert-That 'first seal: every file is listed once, the manifest is not, and paths are in ordinal order' (($paths -join ',') -ceq 'Start.cmd,catalog/catalog-SRV_A.db,engines/Invoke-A.ps1,ui/index.html' -and $paths -notcontains 'package-manifest.json')
    $hashOk = $true
    foreach ($e in $listed) {
        $full = Join-Path $pkg $e.path
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -cne $e.sha256 -or (Get-Item -LiteralPath $full).Length -ne $e.size) { $hashOk = $false }
    }
    Assert-That 'first seal: SHA-256 and size of every file equal an independent computation' $hashOk
    Assert-That 'first seal: catalog block carries server code, schema version, origin and the conversion run' ($m1.catalog.serverCode -ceq 'SRV_A' -and $m1.catalog.schemaVersion -eq 1 -and $m1.catalog.origin -ceq 'conversion-tool' -and $m1.catalog.originReference -ceq 'conversion run 2026-10-05T12:00:00Z' -and $m1.catalog.file -ceq 'catalog/catalog-SRV_A.db')
    Assert-That 'first seal: a catalog written by the converter is not modified' ((Get-FileHash -LiteralPath (Join-Path $pkg 'catalog/catalog-SRV_A.db') -Algorithm SHA256).Hash -eq $catalogBefore)
    Assert-That 'first seal: signature is present and has the shape the contract asks for' ($m1.signature.algorithm -ceq 'TEST-DOUBLE-ECDSA' -and $m1.signature.issuerKeyId -match '^[0-9a-f]{64}$')
    $raw = [System.IO.File]::ReadAllBytes($manifestPath)
    Assert-That 'first seal: the manifest file is ASCII with LF' (-not ($raw | Where-Object { $_ -gt 127 -or $_ -eq 13 }))
    $log = [System.IO.File]::ReadAllText($pkg + '.seal.log')
    Assert-That 'first seal: the log line has package id, version, server, origin, file count and no secret' ($log -like "*package=$($m1.packageId)*version=1.2.3*server=SRV_A*origin=conversion-tool*files=4*signed*" -and -not $log.Contains($marker))
    $v1 = Get-Verification -Dir $pkg
    Assert-That 'verify: a freshly sealed package matches its manifest and the signature verifies' ($v1.Ok -and $v1.Signature -ceq 'valid')

    # 3. Verification catches every kind of change ------------------------------------------------------------------
    $cases = [ordered]@{
        'a changed file'            = { param($d) [System.IO.File]::AppendAllText((Join-Path $d 'ui/index.html'), 'x') }
        'a deleted file'            = { param($d) Remove-Item -LiteralPath (Join-Path $d 'Start.cmd') }
        'an extra file'             = { param($d) [System.IO.File]::WriteAllText((Join-Path $d 'extra.txt'), 'x') }
        'a changed manifest field'  = { param($d) $p = Join-Path $d 'package-manifest.json'; [System.IO.File]::WriteAllText($p, ([System.IO.File]::ReadAllText($p).Replace('1.2.3', '1.2.4'))) }
        'an edited catalog row'     = { param($d) [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $d 'catalog/catalog-SRV_A.db'), "UPDATE cfg_ConfigRule SET ExpectedTemplate = 'edited by hand' WHERE RuleCode = 'R1';")) }
        'a forged signature'        = { param($d) $p = Join-Path $d 'package-manifest.json'; $t = [System.IO.File]::ReadAllText($p); $m = [regex]::Match($t, '"value": "([A-Za-z0-9+/=]+)"'); $v = $m.Groups[1].Value; $f = $v.Substring(0, 10) + $(if ($v[10] -eq 'A') { 'B' } else { 'A' }) + $v.Substring(11); [System.IO.File]::WriteAllText($p, $t.Replace($v, $f)) }
        'a stray temporary file'    = { param($d) [System.IO.File]::WriteAllText((Join-Path $d 'catalog/x.tmp'), 'x') }
    }
    foreach ($name in $cases.Keys) {
        $copy = Join-Path $work ('v-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        Copy-Item -LiteralPath $pkg -Destination $copy -Recurse
        & $cases[$name] $copy
        $v = Get-Verification -Dir $copy
        Assert-That ('verify: ' + $name + ' is detected') (-not $v.Ok -and $v.Problems.Count -ge 1)
    }
    $copy = Join-Path $work 'v-nomanifest'
    Copy-Item -LiteralPath $pkg -Destination $copy -Recurse
    Remove-Item -LiteralPath (Join-Path $copy 'package-manifest.json')
    Assert-That 'verify: a missing manifest is reported' (-not (Get-Verification -Dir $copy).Ok)

    # 4. Re-seal after a manual edit -----------------------------------------------------------------------------------------
    $pkg2 = Join-Path $work 'pkg2'
    Copy-Item -LiteralPath $pkg -Destination $pkg2 -Recurse
    $baseline = Join-Path $work 'baseline.db'
    Copy-Item -LiteralPath (Join-Path $pkg2 'catalog/catalog-SRV_A.db') -Destination $baseline
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $pkg2 'catalog/catalog-SRV_A.db'), "INSERT INTO cfg_ConfigRule VALUES ('R3', 'a rule added by the owner'); UPDATE dbo_ManagedServer SET MachineName = 'HOST-A2';"))
    $r2 = Invoke-TestSeal -Folder $pkg2 -BaselineDb $baseline -NoteText 'added R3 and renamed the host'
    $m2 = Read-ManifestFile -Path (Join-Path $pkg2 'package-manifest.json')
    Assert-That 're-seal: origin becomes manual-edit-sealed, with the note, version kept, new package id' ($m2.catalog.origin -ceq 'manual-edit-sealed' -and $m2.catalog.originReference -like 'manual edit sealed *: added R3 and renamed the host' -and $m2.productVersion -ceq '1.2.3' -and $m2.packageId -cne $m1.packageId)
    $metaRow = Invoke-Sql (Join-Path $pkg2 'catalog/catalog-SRV_A.db') "SELECT source_kind || '|' || built_at_utc FROM catalog_meta;"
    Assert-That 're-seal: catalog_meta records the manual edit and the seal time' ($metaRow -ceq ('manual-edit-sealed|' + $m2.builtAt))
    Assert-That 're-seal: the summary names the two changed tables and no other' ((@($r2.Summary | Where-Object { $_ -like '  table *' }).Count -eq 2) -and (@($r2.Summary | Where-Object { $_ -like '  table cfg_ConfigRule: content changed (rows 2 -> 3)' }).Count -eq 1) -and (@($r2.Summary | Where-Object { $_ -like '  table dbo_ManagedServer: content changed*' }).Count -eq 1) -and (@($r2.Summary | Where-Object { $_ -like '  changed: catalog/catalog-SRV_A.db' }).Count -eq 1))
    Assert-That 're-seal: the summary never contains a cell value' (-not (($r2.Summary -join "`n") -like '*added by the owner*') -and -not (($r2.Summary -join "`n") -like '*HOST-A2*'))
    Assert-That 're-seal: the new manifest verifies and the old signature would not' ((Get-Verification -Dir $pkg2).Ok)
    Assert-That 're-seal: the manifest origin and catalog_meta agree' ((Get-Verification -Dir $pkg2).Problems.Count -eq 0)
    $seals = @([System.IO.File]::ReadAllLines($pkg2 + '.seal.log'))
    Assert-That 're-seal: the log (next to this package folder) has a line for the manual edit' ($seals.Count -eq 1 -and $seals[0] -like '*origin=manual-edit-sealed*' -and $seals[0] -like "*package=$($m2.packageId)*")

    # a change outside the catalog keeps the origin and does not touch the catalog
    $pkg3 = Join-Path $work 'pkg3'
    Copy-Item -LiteralPath $pkg -Destination $pkg3 -Recurse
    [System.IO.File]::AppendAllText((Join-Path $pkg3 'ui/index.html'), '<!-- changed -->')
    $catalogHash3 = (Get-FileHash -LiteralPath (Join-Path $pkg3 'catalog/catalog-SRV_A.db') -Algorithm SHA256).Hash
    $r3 = Invoke-TestSeal -Folder $pkg3
    $m3 = Read-ManifestFile -Path (Join-Path $pkg3 'package-manifest.json')
    Assert-That 're-seal after a non-catalog change: origin stays conversion-tool and the catalog is untouched' ($m3.catalog.origin -ceq 'conversion-tool' -and $m3.catalog.originReference -ceq 'conversion run 2026-10-05T12:00:00Z' -and (Get-FileHash -LiteralPath (Join-Path $pkg3 'catalog/catalog-SRV_A.db') -Algorithm SHA256).Hash -eq $catalogHash3)
    Assert-That 're-seal after a non-catalog change: the summary lists exactly that file' (@($r3.Summary | Where-Object { $_ -like '  changed: *' }).Count -eq 1 -and @($r3.Summary | Where-Object { $_ -like '  changed: ui/index.html' }).Count -eq 1)
    $r3b = Invoke-TestSeal -Folder $pkg3
    $m3b = Read-ManifestFile -Path (Join-Path $pkg3 'package-manifest.json')
    Assert-That 're-seal with no change: new package id, same file entries' ($m3b.packageId -cne $m3.packageId -and ((ConvertTo-CanonicalJson $m3b.files) -ceq (ConvertTo-CanonicalJson $m3.files)))

    # 5. Dry run and confirmation -----------------------------------------------------------------------------------------------
    $pkg4 = Join-Path $work 'pkg4'
    Copy-Item -LiteralPath $pkg3 -Destination $pkg4 -Recurse
    [System.IO.File]::AppendAllText((Join-Path $pkg4 'Start.cmd'), 'echo more' + "`r`n")
    $snap = Get-Folder-Snapshot $pkg4
    $dry = Invoke-TestSeal -Folder $pkg4 -Preview $true
    Assert-That 'dry run: reports what it would do and writes nothing (no manifest change, no log)' (-not $dry.Sealed -and (Get-Folder-Snapshot $pkg4) -ceq $snap -and -not (Test-Path ($pkg4 + '.seal.log')) -and @($dry.Summary | Where-Object { $_ -like '  changed: Start.cmd' }).Count -eq 1)
    Assert-Throws 'without -Yes a non-interactive run is refused' { Invoke-TestSeal -Folder $pkg4 -Confirmed $false } '*Confirmation is needed*'
    Assert-That 'a refused confirmation writes nothing' ((Get-Folder-Snapshot $pkg4) -ceq $snap)

    # 6. Signer problems leave everything as it was -----------------------------------------------------------------------------------
    $pkg5 = Join-Path $work 'pkg5'
    Copy-Item -LiteralPath $pkg -Destination $pkg5 -Recurse
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $pkg5 'catalog/catalog-SRV_A.db'), "UPDATE cfg_ConfigRule SET ExpectedTemplate = 'edited, then the signer fails' WHERE RuleCode = 'R1';"))
    $snap5 = Get-Folder-Snapshot $pkg5
    Assert-Throws 'a signer that fails stops the seal' { Invoke-TestSeal -Folder $pkg5 -Signer $failSignerPath } '*The signer failed*'
    Assert-Throws 'a signer that returns an invalid signature stops the seal' { Invoke-TestSeal -Folder $pkg5 -Signer $badSignerPath } '*invalid signature*'
    Assert-That 'after a signer failure neither the catalog (edited text kept, meta untouched) nor the manifest changed' ((Get-Folder-Snapshot $pkg5) -ceq $snap5)
    Assert-Throws 'no signer and no -Unsigned is refused' { Invoke-TestSeal -Folder $pkg5 -Signer '' } '*No signer was given*'
    Assert-Throws 'a missing signer script is refused' { Invoke-TestSeal -Folder $pkg5 -Signer (Join-Path $work 'nope.ps1') } '*signer script was not found*'

    # 7. Unsigned (development) ------------------------------------------------------------------------------------------------------------
    $pkg6 = Join-Path $work 'pkg6'
    New-TestPackage -Dir $pkg6
    $conv6 = New-ConversionManifest -Dir $pkg6 -Path (Join-Path $work 'conversion6.json')
    $r6 = Invoke-TestSeal -Folder $pkg6 -Signer '' -AllowUnsigned $true -Version '0.0.1' -Conv $conv6
    $m6 = Read-ManifestFile -Path (Join-Path $pkg6 'package-manifest.json')
    $v6 = Get-Verification -Dir $pkg6
    Assert-That '-Unsigned: no signature member, logged as UNSIGNED, and verification fails only because of that' ($null -eq $m6.PSObject.Properties['signature'] -and ([System.IO.File]::ReadAllText($pkg6 + '.seal.log')) -like '*UNSIGNED*' -and -not $v6.Ok -and $v6.Problems.Count -eq 1 -and $v6.Problems[0] -like '*no "signature"*')

    # 8. First-seal rules ---------------------------------------------------------------------------------------------------------------------
    $f1 = Join-Path $work 'first1'; New-TestPackage -Dir $f1
    Assert-Throws 'first seal without -ProductVersion is refused' { Invoke-TestSeal -Folder $f1 -Conv (New-ConversionManifest -Dir $f1 -Path (Join-Path $work 'c-f1.json')) } '*needs -ProductVersion*'
    Assert-Throws 'first seal with a malformed version is refused' { Invoke-TestSeal -Folder $f1 -Version '1.2' -Conv (Join-Path $work 'c-f1.json') } '*semantic version*'
    Assert-Throws 'first seal without a conversion manifest or an origin is refused' { Invoke-TestSeal -Folder $f1 -Version '1.0.0' } '*needs -ConversionManifest*'
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $f1 'catalog/catalog-SRV_A.db'), "UPDATE cfg_ConfigRule SET ExpectedTemplate = 'changed after the conversion' WHERE RuleCode = 'R1';"))
    Assert-Throws 'a catalog changed after the conversion does not match the conversion manifest' { Invoke-TestSeal -Folder $f1 -Version '1.0.0' -Conv (Join-Path $work 'c-f1.json') } '*changed after the conversion*'
    $rf = Invoke-TestSeal -Folder $f1 -Version '1.0.0' -Forced 'manual-edit-sealed'
    Assert-That 'with an explicit origin the same catalog can be sealed, and catalog_meta is updated' ($rf.Sealed -and (Invoke-Sql (Join-Path $f1 'catalog/catalog-SRV_A.db') 'SELECT source_kind FROM catalog_meta;') -ceq 'manual-edit-sealed')

    # 9. Files that must never be in a package ---------------------------------------------------------------------------------------------------
    $badFiles = [ordered]@{
        'credentials.db'         = 'credentials.db'
        'a vault file'           = 'secrets.vault'
        'a certificate with key' = 'cert.pfx'
        'a log'                  = 'run.log'
        'a name with an accent'  = ('caf' + $eAcute + '.txt')
        'a path with a colon'    = 'a:b.txt'
    }
    foreach ($name in $badFiles.Keys) {
        $d = Join-Path $work ('bad-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-TestPackage -Dir $d
        $cv = New-ConversionManifest -Dir $d -Path (Join-Path $d '..' ('c-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json'))
        try { [System.IO.File]::WriteAllText((Join-Path $d $badFiles[$name]), 'x') } catch { Write-Host ('INFO  cannot create {0} on this system, skipped' -f $name); continue }
        Assert-Throws ('refused: ' + $name) { Invoke-TestSeal -Folder $d -Version '1.0.0' -Conv $cv } '*package folder has problems*'
    }
    $caseDir = Join-Path $work 'case'
    New-TestPackage -Dir $caseDir
    [System.IO.File]::WriteAllText((Join-Path $caseDir 'A.txt'), 'x'); [System.IO.File]::WriteAllText((Join-Path $caseDir 'a.txt'), 'y')
    if ((@(Get-ChildItem -LiteralPath $caseDir -Filter '?.txt').Count) -eq 2) {
        Assert-Throws 'refused: two files that differ only by case' { Invoke-TestSeal -Folder $caseDir -Version '1.0.0' -Forced 'build' } '*differs from*only by case*'
    }
    else { Write-Host 'INFO  this file system ignores case, the case-duplicate check is skipped' }
    $linkDir = Join-Path $work 'link'
    New-TestPackage -Dir $linkDir
    $linked = $false
    try { New-Item -ItemType SymbolicLink -Path (Join-Path $linkDir 'link.txt') -Target (Join-Path $linkDir 'Start.cmd') -ErrorAction Stop | Out-Null; $linked = $true } catch { Write-Host 'INFO  cannot create a symbolic link here, the link check is skipped' }
    if ($linked) { Assert-Throws 'refused: a link inside the package' { Invoke-TestSeal -Folder $linkDir -Version '1.0.0' -Forced 'build' } '*link is not allowed*' }

    # 10. Catalog validation ---------------------------------------------------------------------------------------------------------------------------
    $catalogCases = [ordered]@{
        'a secret-like literal in a text cell'  = @{ Sql = ("INSERT INTO cfg_ConfigRule VALUES ('R9', '" + 'Pass' + 'word = ' + $marker + "');"); Like = '*Secret-like literal in cfg_ConfigRule.ExpectedTemplate*' }
        'a secret column'                       = @{ Sql = 'CREATE TABLE cfg_X (Id TEXT NOT NULL PRIMARY KEY, IisIdentityPassword TEXT) STRICT;'; Like = '*Column cfg_X.IisIdentityPassword must not be in a catalog*' }
        'a credential table'                    = @{ Sql = 'CREATE TABLE sec_ManagedCredential (a TEXT) STRICT;'; Like = '*sec_ManagedCredential must not be in a catalog*' }
        'a second catalog_meta row'             = @{ Sql = "PRAGMA ignore_check_constraints = ON; INSERT INTO catalog_meta VALUES (2, 1, 'X', 'build', 'x', '2026-01-01T00:00:00Z', 1);"; Like = '*exactly one row*' }
        'a foreign key violation'               = @{ Sql = 'CREATE TABLE p (id INTEGER PRIMARY KEY) STRICT; CREATE TABLE c (id INTEGER PRIMARY KEY, pid INTEGER REFERENCES p(id)) STRICT; INSERT INTO c VALUES (1, 99);'; Like = '*foreign_key_check*' }
    }
    foreach ($name in $catalogCases.Keys) {
        $d = Join-Path $work ('cat-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-TestPackage -Dir $d
        $cv = New-ConversionManifest -Dir $d -Path (Join-Path $work ('c-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.json'))
        [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $d 'catalog/catalog-SRV_A.db'), $catalogCases[$name].Sql))
        Assert-Throws ('catalog refused: ' + $name) { Invoke-TestSeal -Folder $d -Version '1.0.0' -Forced 'build' } $catalogCases[$name].Like
        Assert-That ('nothing written after: ' + $name) (-not (Test-Path (Join-Path $d 'package-manifest.json')))
    }
    $d = Join-Path $work 'cat-uv'; New-TestPackage -Dir $d
    New-TestCatalog -Path (Join-Path $d 'catalog/catalog-SRV_A.db') -UserVersion 2 -SchemaVersion 2
    Assert-Throws 'catalog refused: an unsupported schema version' { Invoke-TestSeal -Folder $d -Version '1.0.0' -Forced 'build' } '*not a supported schema version*'
    $d = Join-Path $work 'cat-nometa'; New-TestPackage -Dir $d
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $d 'catalog/catalog-SRV_A.db'), 'DROP TABLE catalog_meta;'))
    Assert-Throws 'catalog refused: no catalog_meta' { Invoke-TestSeal -Folder $d -Version '1.0.0' -Forced 'build' } '*no catalog_meta table*'
    $d = Join-Path $work 'cat-notdb'; New-TestPackage -Dir $d
    [System.IO.File]::WriteAllText((Join-Path $d 'catalog/catalog-SRV_A.db'), 'this is not a database')
    Assert-Throws 'catalog refused: not a SQLite file' { Invoke-TestSeal -Folder $d -Version '1.0.0' -Forced 'build' } '*not a SQLite database*'
    $d = Join-Path $work 'cat-code'; Copy-Item -LiteralPath $pkg -Destination $d -Recurse
    [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @((Join-Path $d 'catalog/catalog-SRV_A.db'), "UPDATE catalog_meta SET server_code = 'SRV_OTHER';"))
    Assert-Throws 're-seal refused: catalog_meta.server_code no longer matches the manifest' { Invoke-TestSeal -Folder $d } '*differs from the server code recorded in the manifest*'
    $d = Join-Path $work 'cat-multi'; New-TestPackage -Dir $d
    New-TestCatalog -Path (Join-Path $d 'catalog/catalog-SRV_B.db') -Code 'SRV_B'
    Assert-Throws 'two catalogs in one package need -CatalogRelativePath' { Invoke-TestSeal -Folder $d -Version '1.0.0' -Forced 'build' } '*Exactly one catalog*'
    Assert-Throws 'a note with a non-ASCII character is refused' { Invoke-TestSeal -Folder $pkg -NoteText ('caf' + $eAcute) } '*printable ASCII*'

    # 11. The secret patterns are the converter's -----------------------------------------------------------------------------------------------------------------
    $pwsh = (Get-Process -Id $PID).Path
    $fromConverter = & $pwsh -NoProfile -Command ". '$($convertPath.Replace("'", "''"))' -SyncFile x -OutputFolder y -Sqlite3Path z; Get-SecretPatternTable | ConvertTo-Json -Compress"
    $fromSeal = (Get-SecretPatternTable) | ConvertTo-Json -Compress
    Assert-That 'the secret patterns of the seal tool equal those of the converter (no drift)' ($fromConverter -ceq $fromSeal)
}
finally {
    $ecdsa.Dispose()
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path ([System.IO.Path]::GetTempPath()) 'nonexistent') -ErrorAction SilentlyContinue
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
