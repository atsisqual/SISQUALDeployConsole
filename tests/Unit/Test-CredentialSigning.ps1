#requires -Version 7.0
<#
.SYNOPSIS
    Tests of the vault command, the real signer and the real verifier, and an end-to-end run with the real
    tools/Seal-Package.ps1 (step B6.2b).

.DESCRIPTION
    The scripts run as child processes, as Seal-Package runs them. Vaults live in a temporary folder that is removed
    at the end. The passphrase reaches the children through the test-only environment route (which also needs the
    explicit opt-in variable); marker values stand in for secrets. Needs the sqlite3 executable named by
    SQLITE3_PATH or found on the path. Exits 1 on any failure and 2 when sqlite3 is missing.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite3 = $env:SQLITE3_PATH
if ([string]::IsNullOrWhiteSpace($sqlite3)) { $found = Get-Command sqlite3 -ErrorAction SilentlyContinue; if ($found) { $sqlite3 = $found.Source } }
if ([string]::IsNullOrWhiteSpace($sqlite3) -or -not (Test-Path -LiteralPath $sqlite3 -PathType Leaf)) { Write-Host 'sqlite3 was not found. Set SQLITE3_PATH.'; exit 2 }

$repoTools = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools')).Path
$vaultCmd = Join-Path $repoTools 'Invoke-CredentialVault.ps1'
$signer = Join-Path $repoTools 'Sign-PackageManifest.ps1'
$verifier = Join-Path $repoTools 'Verify-PackageSignature.ps1'
$sealTool = Join-Path $repoTools 'Seal-Package.ps1'
Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path -Force
. $sealTool -PackageFolder 'unused' -Sqlite3Path 'unused'
$pwshPath = (Get-Process -Id $PID).Path

$script:Failures = 0
$script:Passed = 0
function Assert-That { param([string]$Name, [bool]$Condition) if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) } else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) } }
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false; $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}

$goodPass = 'correct horse battery staple 42'
$wrongPass = 'correct horse battery staple 43'
function Invoke-Tool {
    # Runs a script as a child process with a clean SISQUAL_* environment, a closed redirected stdin and a time limit.
    param([string]$Script, [string[]]$Arguments = @(), [hashtable]$Env = @{})
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshPath)
    foreach ($a in @('-NoLogo', '-NoProfile', '-File', $Script) + $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true
    $psi.UseShellExecute = $false
    foreach ($name in @($psi.Environment.Keys | Where-Object { $_ -like 'SISQUAL_*' })) { [void]$psi.Environment.Remove($name) }
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(180000)) { $p.Kill($true); return [pscustomobject]@{ Exit = -1; Out = 'TIMEOUT'; Err = 'TIMEOUT' } }
    return [pscustomobject]@{ Exit = $p.ExitCode; Out = $out.Result; Err = $err.Result }
}
function Get-PassEnv { param([string]$Pass = $goodPass, [hashtable]$More = @{}) $e = @{ SISQUAL_VAULT_PASSPHRASE = $Pass; SISQUAL_ALLOW_ENV_PASSPHRASE = '1' }; foreach ($k in $More.Keys) { $e[$k] = $More[$k] }; return $e }
function Get-Sha { param([string]$Path) return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))) }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-signing-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$vaultFile = Join-Path $root 'vault' 'credential-vault.sisqual'
try {
    # -----------------------------------------------------------------------
    # A. The vault command
    # -----------------------------------------------------------------------
    $init = Invoke-Tool $vaultCmd @('-Action', 'Init', '-VaultPath', $vaultFile) (Get-PassEnv)
    Assert-That 'init: exit 0 and the vault file exists' ($init.Exit -eq 0 -and (Test-Path -LiteralPath $vaultFile))
    Assert-That 'init: shows the issuer key id in 16 groups of 4' ($init.Out -cmatch '(?m)^Issuer key id: ([0-9A-F]{4} ){15}[0-9A-F]{4}\s*$')
    Assert-That 'init: the passphrase is in neither stream' (($init.Out + $init.Err) -cnotlike ('*' + $goodPass + '*'))
    $keyIdGrouped = [regex]::Match($init.Out, '(?m)^Issuer key id: (.+)$').Groups[1].Value.Trim()
    $keyId = ($keyIdGrouped -replace ' ', '').ToLowerInvariant()
    $info = Invoke-Tool $vaultCmd @('-Action', 'Info', '-VaultPath', $vaultFile) (Get-PassEnv)
    Assert-That 'info: exit 0, same key id, a revision, no private material' ($info.Exit -eq 0 -and $info.Out -clike ('*' + $keyIdGrouped + '*') -and $info.Out -cmatch '(?m)^Revision: \d+' -and $info.Out -cnotmatch 'PrivateKey|privateKey')
    $wrong = Invoke-Tool $vaultCmd @('-Action', 'Info', '-VaultPath', $vaultFile) (Get-PassEnv $wrongPass)
    Assert-That 'info: a wrong passphrase is exit 1 with the generic VAULT_OPEN' ($wrong.Exit -eq 1 -and $wrong.Err -clike '*VAULT_COMMAND_FAILED: VAULT_OPEN*' -and ($wrong.Out + $wrong.Err) -cnotlike ('*' + $wrongPass + '*'))
    $again = Invoke-Tool $vaultCmd @('-Action', 'Init', '-VaultPath', $vaultFile) (Get-PassEnv)
    Assert-That 'init: an existing vault is refused and untouched' ($again.Exit -eq 1 -and $again.Err -clike '*VAULT_EXISTS*')
    $noOptIn = Invoke-Tool $vaultCmd @('-Action', 'Info', '-VaultPath', $vaultFile) @{ SISQUAL_VAULT_PASSPHRASE = $goodPass }
    Assert-That 'passphrase: the environment variable without the explicit opt-in is refused' ($noOptIn.Exit -eq 1 -and $noOptIn.Err -clike '*VAULT_PASSPHRASE_INPUT*')
    $noSource = Invoke-Tool $vaultCmd @('-Action', 'Info', '-VaultPath', $vaultFile) @{}
    Assert-That 'passphrase: a redirected input never waits for a prompt (fails closed at once)' ($noSource.Exit -eq 1 -and $noSource.Err -clike '*VAULT_PASSPHRASE_INPUT*')
    $shortPass = Invoke-Tool $vaultCmd @('-Action', 'Init', '-VaultPath', (Join-Path $root 'short' 'v.sisqual')) (Get-PassEnv 'too short')
    Assert-That 'init: a weak passphrase is refused and nothing is created' ($shortPass.Exit -eq 1 -and $shortPass.Err -clike '*VAULT_PASSPHRASE*' -and -not (Test-Path (Join-Path $root 'short')))

    $pubFile = Join-Path $root 'out' 'issuer-public-key.txt'
    $export = Invoke-Tool $vaultCmd @('-Action', 'ExportIssuerKey', '-VaultPath', $vaultFile, '-OutputFile', $pubFile) (Get-PassEnv)
    $parsedKey = ConvertFrom-IssuerPublicKeyText -Text ([IO.File]::ReadAllText($pubFile))
    Assert-That 'export: the public key text parses and carries the vault key id, and the fingerprint is shown' ($export.Exit -eq 0 -and $parsedKey.KeyId -ceq $keyId -and $export.Out -clike ('*' + $keyIdGrouped + '*'))
    Assert-That 'export: the text holds no private key' (([IO.File]::ReadAllText($pubFile)) -cnotmatch 'PRIVATE|PKCS8|privateKey')
    $export2 = Invoke-Tool $vaultCmd @('-Action', 'ExportIssuerKey', '-VaultPath', $vaultFile, '-OutputFile', $pubFile) (Get-PassEnv)
    Assert-That 'export: an existing output file is never overwritten' ($export2.Exit -eq 1 -and $export2.Err -clike '*OUTPUT_EXISTS*')
    $bdir = Join-Path $root 'backups'
    $bk = Invoke-Tool $vaultCmd @('-Action', 'Backup', '-VaultPath', $vaultFile, '-DestinationFolder', $bdir) @{}
    $bakFile = @(Get-ChildItem -LiteralPath $bdir -Filter '*.bak')[0].FullName
    Assert-That 'backup: needs no passphrase, writes an identical copy and shows its SHA-256' ($bk.Exit -eq 0 -and (Get-Sha $bakFile) -ceq (Get-Sha $vaultFile) -and $bk.Out -clike ('*' + (Get-Sha $vaultFile).ToLowerInvariant() + '*'))
    $restoredFile = Join-Path $root 'restored' 'vault.sisqual'
    $rs = Invoke-Tool $vaultCmd @('-Action', 'Restore', '-VaultPath', $restoredFile, '-BackupPath', $bakFile) (Get-PassEnv)
    Assert-That 'restore: with the passphrase a backup comes back identical' ($rs.Exit -eq 0 -and (Get-Sha $restoredFile) -ceq (Get-Sha $bakFile))
    $rsBad = Invoke-Tool $vaultCmd @('-Action', 'Restore', '-VaultPath', (Join-Path $root 'r2' 'v.sisqual'), '-BackupPath', $bakFile) (Get-PassEnv $wrongPass)
    Assert-That 'restore: a wrong passphrase refuses and creates nothing' ($rsBad.Exit -eq 1 -and $rsBad.Err -clike '*VAULT_OPEN*' -and -not (Test-Path (Join-Path $root 'r2' 'v.sisqual')))

    # -----------------------------------------------------------------------
    # B. The real signer
    # -----------------------------------------------------------------------
    [byte[]]$payload = [System.Text.Encoding]::ASCII.GetBytes('{"a":1,"b":"canonical bytes of a manifest"}')
    $inFile = Join-Path $root 'payload.bin'; [IO.File]::WriteAllBytes($inFile, $payload)
    $outFile = Join-Path $root 'sig.json'
    $vaultBefore = Get-Sha $vaultFile
    $sg = Invoke-Tool $signer @('-InputFile', $inFile, '-OutputFile', $outFile) (Get-PassEnv -More @{ SISQUAL_VAULT_PATH = $vaultFile })
    $sigObj = [IO.File]::ReadAllText($outFile) | ConvertFrom-Json -DateKind String
    Assert-That 'signer: exit 0 and a result with exactly issuerKeyId, algorithm and value' ($sg.Exit -eq 0 -and ((($sigObj.PSObject.Properties.Name) -join ',') -ceq 'issuerKeyId,algorithm,value') -and $sigObj.algorithm -ceq 'ECDSA-P256-SHA256' -and $sigObj.issuerKeyId -ceq $keyId)
    Assert-That 'signer: the signature verifies with the public key of the vault' (Test-IssuerSignature -PublicKeySpki $parsedKey.PublicKeySpki -Data $payload -Signature $sigObj)
    Assert-That 'signer: only reads the vault (the file is byte-identical afterwards)' ((Get-Sha $vaultFile) -ceq $vaultBefore)
    Assert-That 'signer: nothing secret in the streams' (($sg.Out + $sg.Err) -cnotlike ('*' + $goodPass + '*'))
    $out2 = Join-Path $root 'sig-bad.json'
    $sgBad = Invoke-Tool $signer @('-InputFile', $inFile, '-OutputFile', $out2) (Get-PassEnv $wrongPass @{ SISQUAL_VAULT_PATH = $vaultFile })
    Assert-That 'signer: a wrong passphrase is exit 1, VAULT_OPEN, and no output file' ($sgBad.Exit -eq 1 -and $sgBad.Err -clike '*SIGNER_FAILED: VAULT_OPEN*' -and -not (Test-Path $out2))
    $sgNoVault = Invoke-Tool $signer @('-InputFile', $inFile, '-OutputFile', $out2) (Get-PassEnv -More @{ SISQUAL_VAULT_PATH = (Join-Path $root 'nothing.sisqual') })
    Assert-That 'signer: a missing vault is exit 1 and no output file' ($sgNoVault.Exit -eq 1 -and -not (Test-Path $out2))
    $sgNoInput = Invoke-Tool $signer @('-InputFile', (Join-Path $root 'missing.bin'), '-OutputFile', $out2) (Get-PassEnv -More @{ SISQUAL_VAULT_PATH = $vaultFile })
    Assert-That 'signer: a missing input is SIGNER_INPUT' ($sgNoInput.Exit -eq 1 -and $sgNoInput.Err -clike '*SIGNER_INPUT*')
    $sgNoPass = Invoke-Tool $signer @('-InputFile', $inFile, '-OutputFile', $out2) @{ SISQUAL_VAULT_PATH = $vaultFile }
    Assert-That 'signer: without a passphrase source and a redirected input it fails closed' ($sgNoPass.Exit -eq 1 -and $sgNoPass.Err -clike '*VAULT_PASSPHRASE_INPUT*' -and -not (Test-Path $out2))

    # -----------------------------------------------------------------------
    # C. The real verifier
    # -----------------------------------------------------------------------
    $keyEnv = @{ SISQUAL_ISSUER_KEY_FILE = $pubFile }
    $v0 = Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile) $keyEnv
    Assert-That 'verifier: a valid signature is exit 0' ($v0.Exit -eq 0)
    $v0b = Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile, '-IssuerKeyFile', $pubFile) @{}
    Assert-That 'verifier: -IssuerKeyFile works without the environment variable' ($v0b.Exit -eq 0)
    $tampered = Join-Path $root 'tampered.bin'; $tb = [byte[]]$payload.Clone(); $tb[5] = $tb[5] -bxor 1; [IO.File]::WriteAllBytes($tampered, $tb)
    $v1 = Invoke-Tool $verifier @('-InputFile', $tampered, '-SignatureFile', $outFile) $keyEnv
    Assert-That 'verifier: altered input is exit 1 (SIGNATURE_INVALID)' ($v1.Exit -eq 1 -and $v1.Err -clike '*SIGNATURE_INVALID*')
    function New-SigFile { param([scriptblock]$Change) $o = [IO.File]::ReadAllText($outFile) | ConvertFrom-Json -AsHashtable -DateKind String; & $Change $o; $f = Join-Path $root ('sig-' + [guid]::NewGuid().ToString('N') + '.json'); [IO.File]::WriteAllText($f, ($o | ConvertTo-Json -Compress)); return $f }
    $sigFlip = New-SigFile { param($o) $b = [Convert]::FromBase64String($o['value']); $b[7] = $b[7] -bxor 1; $o['value'] = [Convert]::ToBase64String($b) }
    Assert-That 'verifier: one flipped bit of the signature is exit 1' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $sigFlip) $keyEnv).Exit -eq 1)
    $sigAlg = New-SigFile { param($o) $o['algorithm'] = 'ECDSA-P256-SHA1' }
    Assert-That 'verifier: another algorithm id is exit 1' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $sigAlg) $keyEnv).Exit -eq 1)
    $sigId = New-SigFile { param($o) $o['issuerKeyId'] = ('0' * 64) }
    Assert-That 'verifier: a key id that is not the pinned key is exit 1 (the key id in the signature is never trusted)' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $sigId) $keyEnv).Exit -eq 1)
    $vaultB = Join-Path $root 'vaultB' 'vault.sisqual'; $pubB = Join-Path $root 'outB' 'pub.txt'
    [void](Invoke-Tool $vaultCmd @('-Action', 'Init', '-VaultPath', $vaultB) (Get-PassEnv))
    [void](Invoke-Tool $vaultCmd @('-Action', 'ExportIssuerKey', '-VaultPath', $vaultB, '-OutputFile', $pubB) (Get-PassEnv))
    Assert-That 'verifier: the pinned key of another issuer is exit 1' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile) @{ SISQUAL_ISSUER_KEY_FILE = $pubB }).Exit -eq 1)
    $vNoKey = Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile) @{ SISQUAL_ISSUER_KEY_FILE = (Join-Path $root 'nokey.txt') }
    Assert-That 'verifier: a missing issuer key file is exit 1 (ISSUER_KEY_FILE)' ($vNoKey.Exit -eq 1 -and $vNoKey.Err -clike '*ISSUER_KEY_FILE*')
    $vNoEnv = Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile) @{}
    Assert-That 'verifier: no issuer key configured at all is exit 1 (nothing is assumed)' ($vNoEnv.Exit -eq 1)
    $badKey = Join-Path $root 'badkey.txt'; [IO.File]::WriteAllText($badKey, ([IO.File]::ReadAllText($pubFile)).Replace('ECDSA-P256', 'ECDSA-P384'))
    Assert-That 'verifier: a corrupt issuer key file is exit 1' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $outFile) @{ SISQUAL_ISSUER_KEY_FILE = $badKey }).Exit -eq 1)
    $garbage = Join-Path $root 'garbage.json'; [IO.File]::WriteAllText($garbage, 'not json')
    Assert-That 'verifier: an unreadable signature file is exit 1' ((Invoke-Tool $verifier @('-InputFile', $inFile, '-SignatureFile', $garbage) $keyEnv).Exit -eq 1)

    # -----------------------------------------------------------------------
    # D. The real Seal-Package with the real signer and verifier
    # -----------------------------------------------------------------------
    $eAcute = [string][char]0x00E9
    function Invoke-Sql { param([string]$Db, [string]$Sql) return (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Db, $Sql)).Trim() }
    function New-TestCatalog {
        param([string]$Path, [string]$Code = 'SRV_A')
        New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
        $sql = @"
CREATE TABLE catalog_meta (meta_id INTEGER PRIMARY KEY CHECK (meta_id = 1), schema_version INTEGER NOT NULL, server_code TEXT NOT NULL, source_kind TEXT NOT NULL, source_reference TEXT NOT NULL, built_at_utc TEXT NOT NULL, cut_rule_version INTEGER NOT NULL) STRICT;
INSERT INTO catalog_meta VALUES (1, 1, '$Code', 'conversion-tool', 'test', '2026-01-01T00:00:00Z', 1);
CREATE TABLE cfg_ConfigRule (RuleCode TEXT NOT NULL PRIMARY KEY, ExpectedTemplate TEXT NOT NULL) STRICT;
INSERT INTO cfg_ConfigRule VALUES ('R1', 'a plain template value');
CREATE TABLE dbo_ManagedServer (ServerCode TEXT NOT NULL PRIMARY KEY, MachineName TEXT NOT NULL) STRICT;
INSERT INTO dbo_ManagedServer VALUES ('$Code', 'HOST-A');
PRAGMA user_version = 1;
"@
        [void](Invoke-Sqlite3 -Exe $sqlite3 -Arguments @($Path, $sql))
    }
    function New-TestPackage {
        param([string]$Dir, [string]$Code = 'SRV_A')
        New-Item -ItemType Directory -Path $Dir -Force | Out-Null
        New-TestCatalog -Path (Join-Path $Dir "catalog/catalog-$Code.db") -Code $Code
        New-Item -ItemType Directory -Path (Join-Path $Dir 'engines') -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $Dir 'engines/Invoke-A.ps1'), [Text.UTF8Encoding]::new($false).GetBytes("# engine`r`nWrite-Host 'accent $eAcute'`r`n"))
        New-Item -ItemType Directory -Path (Join-Path $Dir 'ui') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $Dir 'ui/index.html'), "<html></html>`n")
        [IO.File]::WriteAllText((Join-Path $Dir 'Start.cmd'), "@echo off`r`n")
    }
    function New-ConversionManifest {
        param([string]$Dir, [string]$Code = 'SRV_A', [string]$Path)
        $hash = (Get-FileHash -LiteralPath (Join-Path $Dir "catalog/catalog-$Code.db") -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($Path, (@{ convertedAtUtc = '2026-10-05T12:00:00Z'; catalogs = @(@{ serverCode = $Code; file = "catalog-$Code.db"; sha256 = $hash }) } | ConvertTo-Json -Depth 5))
        return $Path
    }
    function Invoke-RealSeal {
        param([string]$Folder, [string]$Version = '', [string]$Conv = '')
        $r = @(Invoke-Seal -Folder $Folder -Sqlite3 $sqlite3 -Signer $signer -AllowUnsigned $false -Version $Version -CatalogRel '' -ConversionManifestPath $Conv -ForcedOrigin '' -BaselineDb '' -NoteText '' -LogPath '' -Confirmed $true -Preview $false)
        return $r[$r.Count - 1]
    }
    function Get-RealVerification { param([string]$Dir) return (Invoke-PackageVerification -Folder $Dir -Sqlite3 $sqlite3 -Verifier $verifier) }

    $env:SISQUAL_VAULT_PATH = $vaultFile
    $env:SISQUAL_VAULT_PASSPHRASE = $goodPass
    $env:SISQUAL_ALLOW_ENV_PASSPHRASE = '1'
    $env:SISQUAL_ISSUER_KEY_FILE = $pubFile
    $pkg = Join-Path $root 'pkg'
    New-TestPackage -Dir $pkg
    $conv = New-ConversionManifest -Dir $pkg -Path (Join-Path $root 'conversion-manifest.json')
    $sealed = Invoke-RealSeal -Folder $pkg -Version '1.2.3' -Conv $conv
    $manifestPath = Join-Path $pkg 'package-manifest.json'
    Assert-That 'seal: Seal-Package seals with the real signer' ($sealed.Sealed -and (Test-Path $manifestPath))
    $manifest = Read-ManifestFile -Path $manifestPath
    Assert-That 'seal: the manifest signature carries the vault issuer key id and the ECDSA algorithm' ($manifest.signature.issuerKeyId -ceq $keyId -and $manifest.signature.algorithm -ceq 'ECDSA-P256-SHA256')
    $ver = Get-RealVerification -Dir $pkg
    Assert-That 'verify: the real verifier accepts the sealed package' ($ver.Ok -and $ver.Problems.Count -eq 0)
    # independent check of the very bytes Seal-Package signed
    Assert-That 'verify: the signature is valid over the canonical manifest bytes, checked in this process' (Test-IssuerSignature -PublicKeySpki $parsedKey.PublicKeySpki -Data (Get-CanonicalManifestBytes -Manifest $manifest) -Signature $manifest.signature)

    function Copy-Package { param([string]$Name) $d = Join-Path $root $Name; Copy-Item -LiteralPath $pkg -Destination $d -Recurse; return $d }
    $t1 = Copy-Package 'tamper-manifest'
    $mt = [IO.File]::ReadAllText((Join-Path $t1 'package-manifest.json')); [IO.File]::WriteAllText((Join-Path $t1 'package-manifest.json'), $mt.Replace('1.2.3', '1.2.4'))
    Assert-That 'tamper: a changed manifest field fails the verification' (-not (Get-RealVerification -Dir $t1).Ok)
    $t2 = Copy-Package 'tamper-catalog'
    [void](Invoke-Sql (Join-Path $t2 'catalog/catalog-SRV_A.db') "UPDATE cfg_ConfigRule SET ExpectedTemplate = 'changed' WHERE RuleCode = 'R1';")
    Assert-That 'tamper: a changed catalog fails the verification' (-not (Get-RealVerification -Dir $t2).Ok)
    $t3 = Copy-Package 'tamper-engine'
    [IO.File]::AppendAllText((Join-Path $t3 'engines/Invoke-A.ps1'), '# added')
    Assert-That 'tamper: a changed engine file fails the verification' (-not (Get-RealVerification -Dir $t3).Ok)
    $env:SISQUAL_ISSUER_KEY_FILE = $pubB
    Assert-That 'verify: the pinned key of another issuer rejects a package it did not sign' (-not (Get-RealVerification -Dir $pkg).Ok)
    $env:SISQUAL_ISSUER_KEY_FILE = $pubFile
    Assert-That 'verify: with the right key it verifies again (control)' ((Get-RealVerification -Dir $pkg).Ok)
    $pkgWrong = Join-Path $root 'pkg-wrong'; New-TestPackage -Dir $pkgWrong
    $convWrong = New-ConversionManifest -Dir $pkgWrong -Path (Join-Path $root 'conversion-manifest-wrong.json')
    $env:SISQUAL_VAULT_PASSPHRASE = $wrongPass
    Assert-Throws 'seal: a wrong vault passphrase stops the seal at the signer' { Invoke-RealSeal -Folder $pkgWrong -Version '1.0.0' -Conv $convWrong } '*The signer failed*'
    Assert-That 'seal: a failed signer leaves no manifest behind' (-not (Test-Path (Join-Path $pkgWrong 'package-manifest.json')))
}
finally {
    foreach ($n in @('SISQUAL_VAULT_PATH', 'SISQUAL_VAULT_PASSPHRASE', 'SISQUAL_ALLOW_ENV_PASSPHRASE', 'SISQUAL_ISSUER_KEY_FILE')) { Remove-Item -LiteralPath ('Env:' + $n) -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
