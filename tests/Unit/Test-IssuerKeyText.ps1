#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for the issuer public key text of modules/Sisqual.Credentials (step B6.2b).
.DESCRIPTION
    No network, no files. Throw-away keys only. Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path -Force

$script:Failures = 0
$script:Passed = 0
function Assert-That { param([string]$Name, [bool]$Condition) if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) } else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) } }
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false; $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}

$issuer = New-IssuerKeyMaterial
$text = New-IssuerPublicKeyText -PublicKeySpki $issuer.PublicKeySpki
$lines = $text.TrimEnd("`n").Split("`n")
Assert-That 'text: armor, four fields, LF, ASCII' (($lines.Count -eq 6) -and $lines[0] -ceq '-----BEGIN SISQUAL ISSUER KEY-----' -and $lines[5] -ceq '-----END SISQUAL ISSUER KEY-----' -and $text.EndsWith("`n") -and ($text -cnotmatch '[^\x0A\x20-\x7E]'))
Assert-That 'text: field order and algorithm' (($lines[1] -clike 'Contract: *') -and ($lines[2] -ceq ('KeyId: ' + $issuer.KeyId)) -and ($lines[3] -ceq 'KeyAlgorithm: ECDSA-P256') -and ($lines[4] -clike 'PublicKey: *'))
$parsed = ConvertFrom-IssuerPublicKeyText -Text $text
Assert-That 'parse: round trip gives the key id and the same public key bytes' (($parsed.KeyId -ceq $issuer.KeyId) -and ([Convert]::ToHexString($parsed.PublicKeySpki) -ceq [Convert]::ToHexString($issuer.PublicKeySpki)) -and ($parsed.PublicKeySpki -is [byte[]]))
Assert-That 'parse: CRLF (a pasted copy) is accepted' ((ConvertFrom-IssuerPublicKeyText -Text $text.Replace("`n", "`r`n")).KeyId -ceq $issuer.KeyId)
Assert-That 'parse: a missing final newline is accepted' ((ConvertFrom-IssuerPublicKeyText -Text $text.TrimEnd("`n")).KeyId -ceq $issuer.KeyId)
$sig = New-IssuerSignature -PrivateKeyPkcs8 $issuer.PrivateKeyPkcs8 -Data ([byte[]](1, 2, 3))
Assert-That 'parse: the parsed key verifies a signature of the issuer' (Test-IssuerSignature -PublicKeySpki $parsed.PublicKeySpki -Data ([byte[]](1, 2, 3)) -Signature $sig)

function Test-Bad {
    param([string]$Name, [string]$Content)
    Assert-Throws $Name { ConvertFrom-IssuerPublicKeyText -Text $Content }.GetNewClosure() 'Invalid issuer key text.'
}
Test-Bad 'parse: empty text' ''
Test-Bad 'parse: text that is not a key' "hello`nworld`n"
Test-Bad 'parse: wrong BEGIN line' $text.Replace('BEGIN SISQUAL ISSUER KEY', 'BEGIN SISQUAL ISSUER KEYX')
Test-Bad 'parse: wrong END line' $text.Replace('END SISQUAL ISSUER KEY', 'END SISQUAL ISSUER KEYX')
Test-Bad 'parse: text before the armor' ("junk`n" + $text)
Test-Bad 'parse: a missing field' (($lines | Where-Object { $_ -cnotlike 'KeyAlgorithm: *' }) -join "`n")
Test-Bad 'parse: an extra field' ($text.Replace("PublicKey: ", "Extra: 1`nPublicKey: "))
Test-Bad 'parse: fields in another order' (($lines[0], $lines[1], $lines[3], $lines[2], $lines[4], $lines[5]) -join "`n")
Test-Bad 'parse: another contract version' $text.Replace($lines[1], 'Contract: 9.9')
Test-Bad 'parse: another key algorithm' $text.Replace('ECDSA-P256', 'ECDSA-P384')
Test-Bad 'parse: key id in upper case' $text.Replace($issuer.KeyId, $issuer.KeyId.ToUpperInvariant())
$other = New-IssuerKeyMaterial
Test-Bad 'parse: key id of another key (fingerprint is recomputed)' $text.Replace($issuer.KeyId, $other.KeyId)
Test-Bad 'parse: public key of another key' $text.Replace($lines[4], 'PublicKey: ' + [Convert]::ToBase64String($other.PublicKeySpki))
Test-Bad 'parse: public key that is not base64' $text.Replace($lines[4], 'PublicKey: not base64!')
Test-Bad 'parse: a non-ASCII character' ($text.TrimEnd("`n") + "`n" + [string][char]0x00E9 + "`n")
Test-Bad 'parse: a trailing space on a field' $text.Replace($lines[3], $lines[3] + ' ')
Test-Bad 'parse: over the size limit' ($text + ('A' * 3000))
$p384 = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384'))
[byte[]]$p384Spki = $p384.ExportSubjectPublicKeyInfo(); $p384.Dispose()
Assert-Throws 'generate: a P-384 key is refused' { New-IssuerPublicKeyText -PublicKeySpki $p384Spki } '*not an ECDSA P-256 key*'
$ecdh = New-EcdhKeyMaterial
# A forged text: a P-384 key whose key id is the real fingerprint of that key and whose algorithm field says P-256.
$p384b = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384'))
[byte[]]$spki384 = $p384b.ExportSubjectPublicKeyInfo(); $p384b.Dispose()
$forged = ($lines[0], $lines[1], ('KeyId: ' + (Get-PublicKeyFingerprint -PublicKeySpki $spki384)), $lines[3], ('PublicKey: ' + [Convert]::ToBase64String($spki384)), $lines[5]) -join "`n"
Test-Bad 'parse: a P-384 key with a consistent key id is refused (the key itself is validated)' $forged
# Labels are exact: replace each label by another of the same length.
Test-Bad 'parse: a label altered to another of the same length (Contract)' $text.Replace('Contract: ', 'Contrac2: ')
Test-Bad 'parse: a label altered to another of the same length (KeyId)' $text.Replace('KeyId: ', 'KeyIX: ')
Test-Bad 'parse: a label altered to another of the same length (KeyAlgorithm)' $text.Replace('KeyAlgorithm: ', 'KeyAlgorithX: ')
Test-Bad 'parse: a label altered to another of the same length (PublicKey)' $text.Replace('PublicKey: ', 'PublicKeX: ')
Assert-That 'generate: an ECDH key is not an issuer key but is accepted as a P-256 point (the algorithm field is what separates them)' ((New-IssuerPublicKeyText -PublicKeySpki $ecdh.PublicKeySpki) -clike '*KeyAlgorithm: ECDSA-P256*')

Assert-That 'fingerprint display: 16 groups of 4 in upper case' ((Format-KeyFingerprint -Fingerprint $issuer.KeyId) -cmatch '^([0-9A-F]{4} ){15}[0-9A-F]{4}$')
Assert-That 'fingerprint display: the groups give back the fingerprint' (((Format-KeyFingerprint -Fingerprint $issuer.KeyId) -replace ' ', '').ToLowerInvariant() -ceq $issuer.KeyId)
Assert-Throws 'fingerprint display: upper case input is refused' { Format-KeyFingerprint -Fingerprint $issuer.KeyId.ToUpperInvariant() } 'Invalid fingerprint.'
Assert-Throws 'fingerprint display: a short input is refused' { Format-KeyFingerprint -Fingerprint 'abcd' } 'Invalid fingerprint.'

Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
