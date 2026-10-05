#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for modules/Sisqual.Credentials (step B6.1a).

.DESCRIPTION
    No network, no SQL Server, no Windows-only API. Every key is a throw-away key created in memory
    by this test; marker values stand in for secrets. Known-answer values (fingerprint, HKDF key)
    were computed with an independent implementation (Python cryptography). Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path
$sealPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Seal-Package.ps1')).Path
Import-Module $modulePath -Force
$module = Get-Module Sisqual.Credentials

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

# ---------------------------------------------------------------------------
# A. Canonical JSON
# ---------------------------------------------------------------------------
function New-OrdinalDict { return [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal) }
$z = [string][char]0xE9 + '"' + '\' + "`n"
$sample = [ordered]@{ b = 1; a = @('x', $true, $null); c = [ordered]@{ z = $z } }
Assert-That 'canonical: known answer' ((ConvertTo-CanonicalJson $sample) -ceq '{"a":["x",true,null],"b":1,"c":{"z":"\u00e9\"\\\n"}}')
$ordinal = New-OrdinalDict
foreach ($k in @('b', 'B', 'a', '_', '1')) { $ordinal.Add($k, 0) }
Assert-That 'canonical: ordinal key order (digits, upper case, underscore, lower case)' ((ConvertTo-CanonicalJson $ordinal) -ceq '{"1":0,"B":0,"_":0,"a":0,"b":0}')
$caseKeys = New-OrdinalDict
$caseKeys.Add('k' + [string][char]0xE9, 1); $caseKeys.Add('k', 2); $caseKeys.Add('K', 3)
Assert-That 'canonical: keys that differ only by case are all kept' ((ConvertTo-CanonicalJson $caseKeys) -ceq '{"K":3,"k":2,"k\u00e9":1}')
[byte[]]$caseBytes = Get-CanonicalBytes -Value $caseKeys
Assert-That 'canonical bytes: keys that differ only by case are all kept' ([System.Text.Encoding]::ASCII.GetString($caseBytes) -ceq '{"K":3,"k":2,"k\u00e9":1}')
Assert-That 'canonical: empty array and empty object' ((ConvertTo-CanonicalJson ([ordered]@{ e = @(); o = [ordered]@{} })) -ceq '{"e":[],"o":{}}')
Assert-Throws 'canonical: refuses a type it cannot write' { ConvertTo-CanonicalJson ([ordered]@{ d = [datetime]::UtcNow }) } '*cannot be written*'
[byte[]]$cb = Get-CanonicalBytes -Value ([ordered]@{ signature = 'x'; a = 1 }) -ExcludeMember @('signature')
Assert-That 'canonical bytes: byte[] (not object[]), member excluded, ASCII' (($cb -is [byte[]]) -and ([System.Text.Encoding]::ASCII.GetString($cb) -ceq '{"a":1}'))

# Parity with tools/Seal-Package.ps1: take its two functions from the source with the parser, rename them, compare.
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sealPath, [ref]$tokens, [ref]$errors)
$found = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in @('ConvertTo-CanonicalString', 'ConvertTo-CanonicalJson') }, $true))
Assert-That 'parity: both canonical functions found in Seal-Package.ps1' ($found.Count -eq 2)
$source = (($found | ForEach-Object { $_.Extent.Text }) -join "`n") -replace 'ConvertTo-Canonical', 'Seal-ConvertTo-Canonical'
. ([scriptblock]::Create($source))
$battery = @(
    $null, $true, $false, 0, 7, -3, 4294967295, 'plain', '', 'quote " and backslash \ and slash /',
    ("tab`tlf`ncr`rbs" + [string][char]8 + "ff" + [string][char]12),
    ([string][char]0 + [string][char]31 + [string][char]127 + [string][char]0xE9 + [string][char]0x4E2D),
    ([char]::ConvertFromUtf32(0x1F600)),
    @(), @(1, 2, 3), @('a', @('b', @('c'))),
    [ordered]@{ z = 1; y = @{ x = 'v' }; A = @($null, $true) },
    [pscustomobject]@{ name = 'n'; list = @(1, 'two', $false) },
    ('x' * 5000)
)
$same = $true
foreach ($v in $battery) { if ((ConvertTo-CanonicalJson $v) -cne (Seal-ConvertTo-CanonicalJson $v)) { $same = $false } }
Assert-That ('parity: identical output to Seal-Package.ps1 for {0} values' -f $battery.Count) $same

# ---------------------------------------------------------------------------
# B. Helpers
# ---------------------------------------------------------------------------
[byte[]]$zero255 = 0..255 | ForEach-Object { [byte]$_ }
Assert-That 'sha256 and fingerprint: known answer (independent implementation)' (((Get-Sha256Hex -Bytes $zero255) -ceq '40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880') -and ((Get-PublicKeyFingerprint -PublicKeySpki $zero255) -ceq (Get-Sha256Hex -Bytes $zero255)))
Assert-That 'base64: valid text decodes to byte[]' ((ConvertFrom-StrictBase64 -Text 'AQID') -is [byte[]])
foreach ($bad in @('', 'AQI', 'AQ ID', "AQID`n", 'AQI-', 'AQI_', '====', 'AQ==AQ==')) {
    Assert-Throws ('base64: rejects [{0}]' -f ($bad -replace "`n", '\n')) { ConvertFrom-StrictBase64 -Text $bad } 'Invalid base64.'
}
$kat = & $module { Get-EntryContentKey -SharedSecret ([byte[]](0..31)) -EphemeralSpki ([byte[]](0..90)) -MachineSpki ([byte[]](100..190)) }
Assert-That 'HKDF: content key known answer (salt and info, independent implementation)' (([Convert]::ToHexString($kat).ToLowerInvariant()) -ceq '985e60a4cbdbbee77eee91c7877be3b047530b6bef89a8ccb36a76d399e75c38')

# ---------------------------------------------------------------------------
# C. Issuer keys and signatures
# ---------------------------------------------------------------------------
$issuer = New-IssuerKeyMaterial
$issuer2 = New-IssuerKeyMaterial
Assert-That 'issuer key: id is the 64-hex fingerprint of the public key' (($issuer.KeyId -cmatch '^[0-9a-f]{64}$') -and ($issuer.KeyId -ceq (Get-PublicKeyFingerprint -PublicKeySpki $issuer.PublicKeySpki)))
Assert-That 'issuer key: two keys differ' ($issuer.KeyId -cne $issuer2.KeyId)
[byte[]]$data = [System.Text.Encoding]::ASCII.GetBytes('{"a":1}')
$sig = New-IssuerSignature -PrivateKeyPkcs8 $issuer.PrivateKeyPkcs8 -Data $data
Assert-That 'signature: shape and algorithm id' (($sig.algorithm -ceq 'ECDSA-P256-SHA256') -and ($sig.issuerKeyId -ceq $issuer.KeyId) -and ($sig.value -cmatch '^[A-Za-z0-9+/]+={0,2}$') -and ((ConvertFrom-StrictBase64 -Text $sig.value).Length -eq 64))
Assert-That 'signature: verifies' (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $sig)
$sigObject = [pscustomobject]@{ issuerKeyId = $sig.issuerKeyId; algorithm = $sig.algorithm; value = $sig.value }
Assert-That 'signature: verifies when read back as an object (as from JSON)' (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $sigObject)
$sig2 = New-IssuerSignature -PrivateKeyPkcs8 $issuer.PrivateKeyPkcs8 -Data $data
Assert-That 'signature: randomised, both verify' (($sig2.value -cne $sig.value) -and (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $sig2))
[byte[]]$tamperedData = [System.Text.Encoding]::ASCII.GetBytes('{"a":2}')
Assert-That 'signature: altered data fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $tamperedData -Signature $sig))
[byte[]]$raw = ConvertFrom-StrictBase64 -Text $sig.value
$raw[10] = $raw[10] -bxor 1
$flipped = [ordered]@{ issuerKeyId = $sig.issuerKeyId; algorithm = $sig.algorithm; value = [Convert]::ToBase64String($raw) }
Assert-That 'signature: one flipped bit fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $flipped))
Assert-That 'signature: unknown issuer key fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer2.PublicKeySpki -Data $data -Signature $sig))
Assert-That 'signature: other algorithm id fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $sig.issuerKeyId; algorithm = 'ECDSA-P256-SHA1'; value = $sig.value })))
Assert-That 'signature: algorithm id is case sensitive' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $sig.issuerKeyId; algorithm = 'ecdsa-p256-sha256'; value = $sig.value })))
Assert-That 'signature: wrong key id fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $issuer2.KeyId; algorithm = $sig.algorithm; value = $sig.value })))
Assert-That 'signature: key id in upper case fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $sig.issuerKeyId.ToUpperInvariant(); algorithm = $sig.algorithm; value = $sig.value })))
Assert-That 'signature: value that is not base64 fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $sig.issuerKeyId; algorithm = $sig.algorithm; value = 'not base64!' })))
Assert-That 'signature: 63-byte value fails' (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{ issuerKeyId = $sig.issuerKeyId; algorithm = $sig.algorithm; value = [Convert]::ToBase64String($raw[0..62]) })))
Assert-That 'signature: missing members, null and garbage never throw' ((-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature ([ordered]@{}))) -and (-not (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $null)) -and (-not (Test-IssuerSignature -PublicKeySpki ([byte[]](1, 2, 3)) -Data $data -Signature $sig)))
$p384 = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384'))
[byte[]]$p384Private = $p384.ExportPkcs8PrivateKey()
[byte[]]$p384Public = $p384.ExportSubjectPublicKeyInfo()
$p384.Dispose()
Assert-Throws 'signature: refuses to sign with a P-384 key' { New-IssuerSignature -PrivateKeyPkcs8 $p384Private -Data $data } '*not an ECDSA P-256 key*'
Assert-That 'signature: a P-384 public key never verifies' (-not (Test-IssuerSignature -PublicKeySpki $p384Public -Data $data -Signature $sig))

# ---------------------------------------------------------------------------
# D. Credential entries
# ---------------------------------------------------------------------------
$machine = New-EcdhKeyMaterial
$other = New-EcdhKeyMaterial
function New-MachineEcdh { param([byte[]]$Pkcs8) $k = [System.Security.Cryptography.ECDiffieHellman]::Create(); $r = 0; $k.ImportPkcs8PrivateKey($Pkcs8, [ref]$r); return $k }
$machineKey = New-MachineEcdh $machine.PrivateKeyPkcs8
$otherKey = New-MachineEcdh $other.PrivateKeyPkcs8
$packageId = '3f2b8c1e-0a4d-4e6b-9c11-5d7e2a9b4f01'
$serverCode = 'TEST_SERVER'
$ref = 'IIS_IDENTITY.TESTINST'
$fp = $machine.KeyFingerprint
$aad = Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef $ref -Sequence 7

Assert-That 'aad: layout known answer' (([System.Text.Encoding]::ASCII.GetString($aad)) -ceq ("SISQUAL-CRED-AAD-v1`n$packageId`n$serverCode`n$fp`n$ref`n7"))
Assert-That 'aad: byte[]' ($aad -is [byte[]])
Assert-Throws 'aad: upper-case package id refused' { Get-EntryAad -PackageId $packageId.ToUpperInvariant() -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef $ref -Sequence 7 } 'Invalid packageId.'
Assert-Throws 'aad: server code with a space refused' { Get-EntryAad -PackageId $packageId -ServerCode 'BAD CODE' -KeyFingerprint $fp -CredentialRef $ref -Sequence 7 } 'Invalid serverCode.'
Assert-Throws 'aad: short fingerprint refused' { Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint 'abc' -CredentialRef $ref -Sequence 7 } 'Invalid keyFingerprint.'
Assert-Throws 'aad: lower-case credential reference refused' { Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef 'iis_identity' -Sequence 7 } 'Invalid credentialRef.'
Assert-Throws 'aad: sequence 0 refused' { Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef $ref -Sequence 0 } 'Invalid sequence.'

$markerText = 'MARKER-SECRET-9f3a7c21-not-a-real-secret'
[byte[]]$secret = [System.Text.Encoding]::UTF8.GetBytes($markerText)
$captured = @(Protect-CredentialEntry -MachinePublicKeySpki $machine.PublicKeySpki -Secret $secret -Aad $aad *>&1)
Assert-That 'entry: protect returns one object and writes nothing to any stream' ($captured.Count -eq 1)
$entry = $captured[0]
Assert-That 'entry: members and base64 formats' (($entry.Keys -join ',') -ceq 'wrappedKey,nonce,ciphertext' -and ($entry.nonce -cmatch '^[A-Za-z0-9+/]+={0,2}$') -and ((ConvertFrom-StrictBase64 -Text $entry.nonce).Length -eq 12) -and ((ConvertFrom-StrictBase64 -Text $entry.ciphertext).Length -eq ($secret.Length + 16)))
[byte[]]$wrapped = ConvertFrom-StrictBase64 -Text $entry.wrappedKey
$probe = [System.Security.Cryptography.ECDiffieHellman]::Create()
$read = 0
$probe.ImportSubjectPublicKeyInfo($wrapped, [ref]$read)
Assert-That 'entry: wrappedKey is a P-256 SubjectPublicKeyInfo and not the machine key' (($read -eq $wrapped.Length) -and ($probe.KeySize -eq 256) -and ((Get-PublicKeyFingerprint -PublicKeySpki $wrapped) -cne $fp))
$probe.Dispose()
$joined = $entry.wrappedKey + $entry.nonce + $entry.ciphertext
Assert-That 'entry: the secret is not in the output (plain, base64, hex)' (($joined -cnotlike '*MARKER*') -and ($joined -cnotlike ('*' + [Convert]::ToBase64String($secret) + '*')) -and ($joined -cnotlike ('*' + [Convert]::ToHexString($secret) + '*')))
[byte[]]$plain = Unprotect-CredentialEntry -MachineKey $machineKey -Entry $entry -Aad $aad
Assert-That 'entry: round trip returns byte[] equal to the secret' (($plain -is [byte[]]) -and ([System.Text.Encoding]::UTF8.GetString($plain) -ceq $markerText))
$again = Protect-CredentialEntry -MachinePublicKeySpki $machine.PublicKeySpki -Secret $secret -Aad $aad
Assert-That 'entry: same secret twice gives different ephemeral key, nonce and ciphertext' (($again.wrappedKey -cne $entry.wrappedKey) -and ($again.nonce -cne $entry.nonce) -and ($again.ciphertext -cne $entry.ciphertext))
Assert-That 'entry: round trip with the object form (as read from JSON)' ([System.Text.Encoding]::UTF8.GetString((Unprotect-CredentialEntry -MachineKey $machineKey -Entry ([pscustomobject]$entry) -Aad $aad)) -ceq $markerText)

foreach ($length in @(1, 16, 8192)) {
    [byte[]]$s = [byte[]]::new($length)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($s)
    $e = Protect-CredentialEntry -MachinePublicKeySpki $machine.PublicKeySpki -Secret $s -Aad $aad
    [byte[]]$back = Unprotect-CredentialEntry -MachineKey $machineKey -Entry $e -Aad $aad
    Assert-That ('entry: secret of {0} bytes round trips' -f $length) ([Convert]::ToHexString($back) -ceq [Convert]::ToHexString($s))
}
Assert-Throws 'entry: empty secret refused' { Protect-CredentialEntry -MachinePublicKeySpki $machine.PublicKeySpki -Secret ([byte[]]@()) -Aad $aad } '*unsupported length*'
Assert-Throws 'entry: 8193-byte secret refused' { Protect-CredentialEntry -MachinePublicKeySpki $machine.PublicKeySpki -Secret ([byte[]]::new(8193)) -Aad $aad } '*unsupported length*'
Assert-Throws 'entry: refuses a public key that is not P-256' { Protect-CredentialEntry -MachinePublicKeySpki $p384Public -Secret $secret -Aad $aad } '*not an ECDH P-256 key*'

# Wrong machine, altered parts and altered context all fail with the same generic reason.
Assert-Throws 'entry: another machine key cannot decrypt (package for machine A on machine B)' { Unprotect-CredentialEntry -MachineKey $otherKey -Entry $entry -Aad $aad } 'DECRYPT'
$variants = [ordered]@{
    'packageId'      = (Get-EntryAad -PackageId '00000000-0000-4000-8000-000000000000' -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef $ref -Sequence 7)
    'serverCode'     = (Get-EntryAad -PackageId $packageId -ServerCode 'OTHER_SERVER' -KeyFingerprint $fp -CredentialRef $ref -Sequence 7)
    'keyFingerprint' = (Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $other.KeyFingerprint -CredentialRef $ref -Sequence 7)
    'credentialRef'  = (Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef 'WEB_ACCESS.TESTINST' -Sequence 7)
    'sequence'       = (Get-EntryAad -PackageId $packageId -ServerCode $serverCode -KeyFingerprint $fp -CredentialRef $ref -Sequence 8)
}
foreach ($name in $variants.Keys) {
    $v = $variants[$name]
    Assert-Throws ('entry: changed {0} in the associated data fails' -f $name) { Unprotect-CredentialEntry -MachineKey $machineKey -Entry $entry -Aad $v } 'DECRYPT'
}
function Copy-Entry { param($Source, [string]$Member, [string]$Value) $c = [ordered]@{ wrappedKey = $Source.wrappedKey; nonce = $Source.nonce; ciphertext = $Source.ciphertext }; $c[$Member] = $Value; return $c }
[byte[]]$ct = ConvertFrom-StrictBase64 -Text $entry.ciphertext
$ct[0] = $ct[0] -bxor 1
Assert-Throws 'entry: flipped ciphertext bit fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'ciphertext' ([Convert]::ToBase64String($ct))) -Aad $aad } 'DECRYPT'
[byte[]]$ct2 = ConvertFrom-StrictBase64 -Text $entry.ciphertext
$ct2[$ct2.Length - 1] = $ct2[$ct2.Length - 1] -bxor 1
Assert-Throws 'entry: flipped tag bit fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'ciphertext' ([Convert]::ToBase64String($ct2))) -Aad $aad } 'DECRYPT'
[byte[]]$nn = ConvertFrom-StrictBase64 -Text $entry.nonce
$nn[0] = $nn[0] -bxor 1
Assert-Throws 'entry: flipped nonce bit fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'nonce' ([Convert]::ToBase64String($nn))) -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: another valid ephemeral key fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'wrappedKey' ([Convert]::ToBase64String($other.PublicKeySpki))) -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: truncated ciphertext fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'ciphertext' 'AAAA') -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: wrong nonce length fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'nonce' 'AAAAAAAAAAAAAAAA') -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: garbage wrappedKey fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'wrappedKey' 'AAAA') -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: base64 with whitespace fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry (Copy-Entry $entry 'nonce' ($entry.nonce + ' ')) -Aad $aad } 'DECRYPT'
Assert-Throws 'entry: missing member fails' { Unprotect-CredentialEntry -MachineKey $machineKey -Entry ([ordered]@{ nonce = $entry.nonce; ciphertext = $entry.ciphertext }) -Aad $aad } 'DECRYPT'
$failText = ''
try { Unprotect-CredentialEntry -MachineKey $otherKey -Entry $entry -Aad $aad } catch { $failText = $_.Exception.Message + ($_ | Out-String) }
Assert-That 'entry: a failure never contains the marker or key material' (($failText -cnotlike '*MARKER*') -and ($failText -cnotlike ('*' + $entry.ciphertext + '*')))

$machineKey.Dispose()
$otherKey.Dispose()
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
