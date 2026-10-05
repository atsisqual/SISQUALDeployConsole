#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for the machine identity text, the credential package and its validation
    (modules/Sisqual.Credentials, step B6.1b; contract sections 3a, 4, 6 and 7).

.DESCRIPTION
    No network, no SQL Server, no Windows-only API. Every key is a throw-away key created in memory;
    the marker values stand in for secrets. Packages that break the policy on purpose are built with
    the module's internal signer, so that only the check under test can fail. Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path
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
# Fixtures
# ---------------------------------------------------------------------------
$issuer = New-IssuerKeyMaterial
$issuer2 = New-IssuerKeyMaterial
$machineA = New-EcdhKeyMaterial
$machineB = New-EcdhKeyMaterial
function New-EcdhFromPkcs8 { param([byte[]]$Pkcs8) $k = [System.Security.Cryptography.ECDiffieHellman]::Create(); $r = 0; $k.ImportPkcs8PrivateKey($Pkcs8, [ref]$r); return $k }
$keyA = New-EcdhFromPkcs8 $machineA.PrivateKeyPkcs8
$keyB = New-EcdhFromPkcs8 $machineB.PrivateKeyPkcs8
$serverCode = 'TEST_SERVER'
$issued = [datetime]::new(2026, 10, 6, 10, 0, 0, [System.DateTimeKind]::Utc)
$now = $issued.AddHours(1)
$markers = [ordered]@{
    'IIS_IDENTITY.INST1'     = 'MARKER-IIS-4d1e9a-not-a-real-secret'
    'WEB_ACCESS.INST1'       = 'MARKER-WEB-77b2c3-not-a-real-secret'
    'MOBILE_APP_TOKEN.INST1' = 'MARKER-TOK-0c8f5e-not-a-real-secret'
    'RULE_SECRET.SOME_RULE'  = 'MARKER-RUL-93a6d0-not-a-real-secret'
}
function New-TestEntries {
    $list = @(
        @{ CredentialRef = 'IIS_IDENTITY.INST1'; Kind = 'IIS_IDENTITY'; InstanceCode = 'INST1'; Secret = [System.Text.Encoding]::UTF8.GetBytes($markers['IIS_IDENTITY.INST1']) },
        @{ CredentialRef = 'WEB_ACCESS.INST1'; Kind = 'WEB_ACCESS'; InstanceCode = 'INST1'; Secret = [System.Text.Encoding]::UTF8.GetBytes($markers['WEB_ACCESS.INST1']) },
        @{ CredentialRef = 'MOBILE_APP_TOKEN.INST1'; Kind = 'MOBILE_APP_TOKEN'; InstanceCode = 'INST1'; Secret = [System.Text.Encoding]::UTF8.GetBytes($markers['MOBILE_APP_TOKEN.INST1']) },
        @{ CredentialRef = 'RULE_SECRET.SOME_RULE'; Kind = 'RULE_SECRET'; Secret = [System.Text.Encoding]::UTF8.GetBytes($markers['RULE_SECRET.SOME_RULE']) }
    )
    return , $list
}
function New-GoodPackage {
    param([long]$Sequence = 5, [byte[]]$MachineSpki = $machineA.PublicKeySpki, [byte[]]$IssuerKey = $issuer.PrivateKeyPkcs8, [string]$Server = $serverCode)
    return (New-CredentialPackage -IssuerPrivateKeyPkcs8 $IssuerKey -TargetServerCode $Server -TargetMachinePublicKeySpki $MachineSpki -TargetMachineName 'TEST-HOST' -Sequence $Sequence -Entries (New-TestEntries) -IssuedAt $issued)
}
function Invoke-Validate {
    param([string]$Text, [byte[]]$IssuerSpki = $issuer.PublicKeySpki, [string]$Server = $serverCode, [string]$Fingerprint = $machineA.KeyFingerprint, [datetime]$At = $now, [long]$Last = 4)
    return (Test-CredentialPackage -Text $Text -TrustedIssuerPublicKeySpki $IssuerSpki -ServerCode $Server -MachineKeyFingerprint $Fingerprint -Now $At -LastAcceptedSequence $Last)
}
function Assert-Reason {
    param([string]$Name, $Result, [string]$Reason)
    Assert-That $Name (($Result.Ok -eq $false) -and ($Result.Reason -ceq $Reason) -and ($null -eq $Result.Package))
}
function Get-Body { param([string]$Text) return (& $module { param($t) ConvertFrom-PackageText -Text $t } $Text) }
function Sign-Body { param($Body, [byte[]]$Key = $issuer.PrivateKeyPkcs8) return (& $module { param($b, $k) New-SignedPackageText -Body $b -IssuerPrivateKeyPkcs8 $k } $Body $Key) }
function Armor-Json { param([string]$Json) return (& $module { param($j) ConvertTo-PackageArmor -JsonBytes ([System.Text.Encoding]::ASCII.GetBytes($j)) } $Json) }
function Raw-Body { param($Body) return (Armor-Json (ConvertTo-CanonicalJson $Body)) }

$good = New-GoodPackage
$goodBody = Get-Body $good

# ---------------------------------------------------------------------------
# A. A good package
# ---------------------------------------------------------------------------
$lines = $good.Split("`n")
Assert-That 'package: ASCII, LF only, armor, lines of at most 76 characters' (($good -cnotmatch '[^\x0A\x20-\x7E]') -and ($lines[0] -ceq '-----BEGIN SISQUAL CREDENTIAL PACKAGE-----') -and ($lines[-2] -ceq '-----END SISQUAL CREDENTIAL PACKAGE-----') -and (@($lines[1..($lines.Count - 3)] | Where-Object { $_.Length -gt 76 }).Count -eq 0) -and ($good.Length -lt 262144))
$bodyBytes = [Convert]::FromBase64String(($lines[1..($lines.Count - 3)] -join ''))
Assert-That 'package: the body is the canonical JSON of the whole object (signature included)' ([System.Text.Encoding]::ASCII.GetString($bodyBytes) -ceq (ConvertTo-CanonicalJson $goodBody))
$leak = $true
foreach ($m in $markers.Values) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($m)
    if (($good -clike ('*' + $m + '*')) -or ($good -clike ('*' + [Convert]::ToBase64String($b) + '*')) -or ($good -clike ('*' + [Convert]::ToHexString($b) + '*'))) { $leak = $false }
}
Assert-That 'package: no secret in the text (plain, base64, hex)' $leak
$captured = @(Invoke-Validate -Text $good *>&1)
Assert-That 'validate: accepts a good package, one result and nothing on any stream' (($captured.Count -eq 1) -and $captured[0].Ok -and ($null -eq $captured[0].Reason))
$ok = $captured[0]
Assert-That 'validate: the package comes back with its four entries' (($ok.Package['entries'].Count -eq 4) -and ($ok.Package['sequence'] -eq 5) -and ($ok.Package['target']['serverCode'] -ceq $serverCode))
Assert-That 'validate: the result never carries a secret' (((($ok | Out-String)) -cnotlike '*MARKER*'))
foreach ($ref in $markers.Keys) {
    [byte[]]$plain = Get-PackageEntrySecret -Package $ok.Package -CredentialRef $ref -MachineKey $keyA
    Assert-That ('decrypt: {0}' -f $ref) ([System.Text.Encoding]::UTF8.GetString($plain) -ceq $markers[$ref])
}
Assert-Throws 'decrypt: unknown reference' { Get-PackageEntrySecret -Package $ok.Package -CredentialRef 'IIS_IDENTITY.NOPE' -MachineKey $keyA } 'DECRYPT'
Assert-Throws 'decrypt: reference in another case' { Get-PackageEntrySecret -Package $ok.Package -CredentialRef 'iis_identity.inst1' -MachineKey $keyA } 'DECRYPT'
Assert-Throws 'decrypt: with the key of another machine' { Get-PackageEntrySecret -Package $ok.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyB } 'DECRYPT'
Assert-That 'validate: accepts CRLF line endings (text pasted from a browser)' ((Invoke-Validate -Text $good.Replace("`n", "`r`n")).Ok)
Assert-That 'validate: accepts the text without the final line feed' ((Invoke-Validate -Text $good.TrimEnd("`n")).Ok)
Assert-That 'validate: lower sequence boundary (last accepted 4, package 5)' ((Invoke-Validate -Text $good -Last 4).Ok)
Assert-That 'validate: expiry boundary is inclusive' ((Invoke-Validate -Text $good -At $issued.AddDays(365)).Ok)
Assert-That 'validate: issuedAt 14 minutes in the future is tolerated' ((Invoke-Validate -Text $good -At $issued.AddMinutes(-14)).Ok)
$again = New-GoodPackage
Assert-That 'build: two packages differ (package id, ciphertext) and both validate' (($again -cne $good) -and (Invoke-Validate -Text $again).Ok)

# ---------------------------------------------------------------------------
# B. Negative tests of contract section 7
# ---------------------------------------------------------------------------
Assert-Reason 'section 7: package for machine A on machine B (same folder copied) fails at check 5' (Invoke-Validate -Text $good -Fingerprint $machineB.KeyFingerprint) 'TARGET_KEY'
function Test-Altered {
    param([string]$Name, [scriptblock]$Change)
    $b = Get-Body $good
    & $Change $b
    Assert-Reason ('section 7: altered body ({0}) fails at check 3' -f $Name) (Invoke-Validate -Text (Raw-Body $b)) 'SIGNATURE'
}
Test-Altered 'one ciphertext bit' { param($b) $c = [Convert]::FromBase64String($b['entries'][1]['ciphertext']); $c[2] = $c[2] -bxor 1; $b['entries'][1]['ciphertext'] = [Convert]::ToBase64String($c) }
Test-Altered 'metadata: machine name' { param($b) $b['target']['machineName'] = 'OTHER-HOST' }
Test-Altered 'metadata: credential reference' { param($b) $b['entries'][0]['credentialRef'] = 'IIS_IDENTITY.INST2' }
Test-Altered 'metadata: kind' { param($b) $b['entries'][0]['kind'] = 'WEB_ACCESS' }
Test-Altered 'metadata: instance code' { param($b) $b['entries'][0]['instanceCode'] = 'INST2' }
Test-Altered 'sequence raised' { param($b) $b['sequence'] = [long]6 }
Test-Altered 'expiry extended' { param($b) $b['expiresAt'] = '2027-10-07T10:00:00Z' }
Test-Altered 'an entry removed' { param($b) $b['entries'] = @($b['entries'][0..2]) }
Test-Altered 'an entry duplicated' { param($b) $b['entries'] = @($b['entries'][0], $b['entries'][0]) + @($b['entries'][1..3]) }
Test-Altered 'issuer key id' { param($b) $b['issuer']['keyId'] = $issuer2.KeyId }
$flip = Get-Body $good
$sv = [Convert]::FromBase64String($flip['signature']['value']); $sv[5] = $sv[5] -bxor 1; $flip['signature']['value'] = [Convert]::ToBase64String($sv)
Assert-Reason 'section 7: altered signature fails at check 3' (Invoke-Validate -Text (Raw-Body $flip)) 'SIGNATURE'
$sigAlg = Get-Body $good; $sigAlg['signature']['algorithm'] = 'ECDSA-P256-SHA1'
Assert-Reason 'section 7: other signature algorithm fails at check 3' (Invoke-Validate -Text (Raw-Body $sigAlg)) 'SIGNATURE'
Assert-Reason 'section 7: replay with the same sequence fails at check 7' (Invoke-Validate -Text $good -Last 5) 'REPLAY'
Assert-Reason 'section 7: replay with a higher installed sequence fails at check 7' (Invoke-Validate -Text $good -Last 6) 'REPLAY'
Assert-Reason 'section 7: expired package fails at check 6' (Invoke-Validate -Text $good -At $issued.AddDays(365).AddSeconds(1)) 'TIME_WINDOW'
$future = New-CredentialPackage -IssuerPrivateKeyPkcs8 $issuer.PrivateKeyPkcs8 -TargetServerCode $serverCode -TargetMachinePublicKeySpki $machineA.PublicKeySpki -Sequence 5 -Entries (New-TestEntries) -IssuedAt $issued -NotBefore $issued.AddDays(1)
Assert-Reason 'section 7: package not yet valid (notBefore) fails at check 6' (Invoke-Validate -Text $future) 'TIME_WINDOW'
Assert-That 'section 7: notBefore equal to now is valid' ((Invoke-Validate -Text $future -At $issued.AddDays(1)).Ok)
Assert-Reason 'section 7: issuedAt 16 minutes in the future fails at check 6' (Invoke-Validate -Text $good -At $issued.AddMinutes(-16)) 'TIME_WINDOW'
Assert-Reason 'section 7: wrong server code fails at check 4' (Invoke-Validate -Text $good -Server 'OTHER_SERVER') 'TARGET_SERVER'
Assert-Reason 'section 7: server code in another case fails at check 4' (Invoke-Validate -Text $good -Server 'test_server') 'TARGET_SERVER'
Assert-Reason 'section 7: signed by an unknown issuer key fails at check 3' (Invoke-Validate -Text $good -IssuerSpki $issuer2.PublicKeySpki) 'SIGNATURE'
$claimed = Get-Body $good; $claimed['issuer']['keyId'] = $issuer.KeyId
Assert-Reason 'section 7: signed by another key but claiming the trusted key id fails at check 3' (Invoke-Validate -Text (Sign-Body $claimed $issuer2.PrivateKeyPkcs8)) 'SIGNATURE'

# Lifetime and policy: the builder refuses, the validator also refuses a package that was signed anyway.
$long = Get-Body $good; $long['expiresAt'] = '2027-10-08T10:00:00Z'
Assert-Reason 'validate: lifetime of 367 days fails at check 6 even when signed' (Invoke-Validate -Text (Sign-Body $long) -At $issued.AddDays(30)) 'TIME_WINDOW'
$edge = Get-Body $good; $edge['expiresAt'] = '2027-10-07T10:00:00Z'
Assert-That 'validate: lifetime of exactly 366 days is accepted' ((Invoke-Validate -Text (Sign-Body $edge) -At $issued.AddDays(30)).Ok)
$backwards = Get-Body $good; $backwards['expiresAt'] = '2026-10-06T09:00:00Z'
Assert-Reason 'validate: expiry before issue fails at check 6' (Invoke-Validate -Text (Sign-Body $backwards) -At $issued.AddMinutes(-1)) 'TIME_WINDOW'

# Check 8 and check 2
$dup = Get-Body $good; $dup['entries'][1]['credentialRef'] = $dup['entries'][0]['credentialRef']
Assert-Reason 'validate: duplicate credential reference fails at check 8' (Invoke-Validate -Text (Sign-Body $dup)) 'DUPLICATE_REF'
$ver = Get-Body $good; $ver['contractVersion'] = '9.9-test'
Assert-Reason 'validate: unsupported contract version fails at check 2' (Invoke-Validate -Text (Sign-Body $ver)) 'VERSION'
$kw = Get-Body $good; $kw['encryption']['keyWrap'] = 'ECDH-ES-P256-HKDF-SHA512'
Assert-Reason 'validate: other key wrap identifier fails at check 2' (Invoke-Validate -Text (Sign-Body $kw)) 'VERSION'
$ct = Get-Body $good; $ct['encryption']['content'] = 'AES-128-GCM'
Assert-Reason 'validate: other content identifier fails at check 2' (Invoke-Validate -Text (Sign-Body $ct)) 'VERSION'

# ---------------------------------------------------------------------------
# C. The first failing check wins (order of section 6)
# ---------------------------------------------------------------------------
Assert-Reason 'order: wrong server + wrong key + expired -> TARGET_SERVER' (Invoke-Validate -Text $good -Server 'OTHER_SERVER' -Fingerprint $machineB.KeyFingerprint -At $issued.AddDays(400)) 'TARGET_SERVER'
Assert-Reason 'order: wrong key + expired -> TARGET_KEY' (Invoke-Validate -Text $good -Fingerprint $machineB.KeyFingerprint -At $issued.AddDays(400)) 'TARGET_KEY'
Assert-Reason 'order: expired + replay -> TIME_WINDOW' (Invoke-Validate -Text $good -At $issued.AddDays(400) -Last 9) 'TIME_WINDOW'
$replayDup = Get-Body $good; $replayDup['entries'][1]['credentialRef'] = $replayDup['entries'][0]['credentialRef']
Assert-Reason 'order: replay + duplicate reference -> REPLAY' (Invoke-Validate -Text (Sign-Body $replayDup) -Last 9) 'REPLAY'
Assert-Reason 'order: unknown issuer + wrong server -> SIGNATURE' (Invoke-Validate -Text $good -IssuerSpki $issuer2.PublicKeySpki -Server 'OTHER_SERVER') 'SIGNATURE'
$verBad = Get-Body $good; $verBad['contractVersion'] = '9.9-test'
Assert-Reason 'order: bad version + unknown issuer -> VERSION' (Invoke-Validate -Text (Sign-Body $verBad) -IssuerSpki $issuer2.PublicKeySpki) 'VERSION'
$fmtBad = Get-Body $good; $fmtBad['packageId'] = $fmtBad['packageId'].ToUpperInvariant(); $fmtBad['contractVersion'] = '9.9-test'
Assert-Reason 'order: bad format + bad version -> FORMAT' (Invoke-Validate -Text (Sign-Body $fmtBad)) 'FORMAT'

# ---------------------------------------------------------------------------
# D. Format failures (check 1)
# ---------------------------------------------------------------------------
$begin = '-----BEGIN SISQUAL CREDENTIAL PACKAGE-----'
$end = '-----END SISQUAL CREDENTIAL PACKAGE-----'
$formatCases = [ordered]@{
    'empty text'                 = ''
    'only spaces'                = '   '
    'no begin line'              = $good.Substring($begin.Length + 1)
    'no end line'                = $good.Substring(0, $good.IndexOf($end))
    'text before the begin line' = ("hello`n" + $good)
    'text after the end line'    = ($good + "tail`n")
    'machine identity armor'     = $good.Replace('CREDENTIAL PACKAGE', 'MACHINE IDENTITY')
    'non-ASCII character'        = $good.Replace($lines[1], $lines[1].Substring(0, 10) + [string][char]0xE9 + $lines[1].Substring(11))
    'lone carriage return'       = $good.Replace($lines[1] + "`n", $lines[1] + "`r")
    'line of 77 characters'      = $good.Replace($lines[1] + "`n", $lines[1] + 'A' + "`n")
    'empty body'                 = ($begin + "`n" + $end + "`n")
    'space inside a body line'   = $good.Replace($lines[1], $lines[1].Substring(0, 8) + ' ' + $lines[1].Substring(8))
    'base64 padding in the middle' = ($begin + "`nAAAA=AAA`n" + $end + "`n")
    'url-safe base64'            = $good.Replace($lines[1], $lines[1].Replace('+', '-').Replace('/', '_') + '-')
    'more than 256 KiB'          = ($begin + "`n" + ((('A' * 76) + "`n") * 3500) + $end + "`n")
    'body is not JSON'           = (Armor-Json 'this is not json')
    'JSON array instead of object' = (Armor-Json '[1,2,3]')
    'JSON null'                  = (Armor-Json 'null')
    'duplicate member'           = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).Replace('"sequence":5', '"sequence":5,"sequence":6')))
    'sequence as a float'        = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).Replace('"sequence":5', '"sequence":5.0')))
    'sequence with exponent'     = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).Replace('"sequence":5', '"sequence":5e0')))
    'sequence beyond int64'      = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).Replace('"sequence":5', '"sequence":9223372036854775808')))
    'sequence as text'           = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).Replace('"sequence":5', '"sequence":"5"')))
    'JSON with a comment'        = (Armor-Json ('/*x*/' + (ConvertTo-CanonicalJson $goodBody)))
    'JSON with a trailing comma' = (Armor-Json ((ConvertTo-CanonicalJson $goodBody).TrimEnd('}') + ',}'))
}
foreach ($name in $formatCases.Keys) { Assert-Reason ('format: {0}' -f $name) (Invoke-Validate -Text $formatCases[$name]) 'FORMAT' }
$nullResult = Test-CredentialPackage -Text $null -TrustedIssuerPublicKeySpki $issuer.PublicKeySpki -ServerCode $serverCode -MachineKeyFingerprint $machineA.KeyFingerprint
Assert-Reason 'format: null text never throws' $nullResult 'FORMAT'

$mutations = [ordered]@{
    'unknown member at the top'     = { param($b) $b['extra'] = 'x' }
    'unknown member in issuer'      = { param($b) $b['issuer']['extra'] = 'x' }
    'unknown member in target'      = { param($b) $b['target']['extra'] = 'x' }
    'unknown member in encryption'  = { param($b) $b['encryption']['extra'] = 'x' }
    'unknown member in an entry'    = { param($b) $b['entries'][0]['aad'] = 'x' }
    'case variant of a member'      = { param($b) $b['Sequence'] = $b['sequence']; $b.Remove('sequence') }
    'case variant in an entry'      = { param($b) $b['entries'][0]['Kind'] = $b['entries'][0]['kind']; $b['entries'][0].Remove('kind') }
    'missing contractVersion'       = { param($b) $b.Remove('contractVersion') }
    'missing packageId'             = { param($b) $b.Remove('packageId') }
    'missing sequence'              = { param($b) $b.Remove('sequence') }
    'missing issuedAt'              = { param($b) $b.Remove('issuedAt') }
    'missing expiresAt'             = { param($b) $b.Remove('expiresAt') }
    'missing issuer'                = { param($b) $b.Remove('issuer') }
    'missing target'                = { param($b) $b.Remove('target') }
    'missing encryption'            = { param($b) $b.Remove('encryption') }
    'missing entries'               = { param($b) $b.Remove('entries') }
    'missing signature'             = { param($b) $b.Remove('signature') }
    'missing nonce in an entry'     = { param($b) $b['entries'][2].Remove('nonce') }
    'upper-case package id'         = { param($b) $b['packageId'] = $b['packageId'].ToUpperInvariant() }
    'sequence 0'                    = { param($b) $b['sequence'] = [long]0 }
    'negative sequence'             = { param($b) $b['sequence'] = [long]-3 }
    'time with a space'             = { param($b) $b['issuedAt'] = '2026-10-06 10:00:00' }
    'time with an offset'           = { param($b) $b['issuedAt'] = '2026-10-06T10:00:00+00:00' }
    'impossible date'               = { param($b) $b['expiresAt'] = '2026-13-45T10:00:00Z' }
    'server code with a space'      = { param($b) $b['target']['serverCode'] = 'BAD CODE' }
    'upper-case fingerprint'        = { param($b) $b['target']['keyFingerprint'] = $b['target']['keyFingerprint'].ToUpperInvariant() }
    'short issuer key id'           = { param($b) $b['issuer']['keyId'] = 'abc' }
    'machine name with a space'     = { param($b) $b['target']['machineName'] = 'BAD HOST' }
    'unknown credential kind'       = { param($b) $b['entries'][0]['kind'] = 'OTHER' }
    'lower-case credential ref'     = { param($b) $b['entries'][0]['credentialRef'] = 'iis_identity.inst1' }
    'instance code with a space'    = { param($b) $b['entries'][0]['instanceCode'] = 'IN ST' }
    'no entries'                    = { param($b) $b['entries'] = @() }
    'entries is an object'          = { param($b) $b['entries'] = $b['entries'][0] }
    'entries is a string'           = { param($b) $b['entries'] = 'x' }
    'nonce of 11 bytes'             = { param($b) $b['entries'][0]['nonce'] = [Convert]::ToBase64String([byte[]]::new(11)) }
    'wrappedKey of 90 bytes'        = { param($b) $b['entries'][0]['wrappedKey'] = [Convert]::ToBase64String([byte[]]::new(90)) }
    'ciphertext of 16 bytes'        = { param($b) $b['entries'][0]['ciphertext'] = [Convert]::ToBase64String([byte[]]::new(16)) }
    'ciphertext not base64'         = { param($b) $b['entries'][0]['ciphertext'] = 'not base64!' }
    'short signature value'         = { param($b) $b['signature']['value'] = 'AAAA' }
    'signature algorithm too short' = { param($b) $b['signature']['algorithm'] = 'EC' }
    'version with a space'          = { param($b) $b['contractVersion'] = '0.1 proposed' }
    'target is a string'            = { param($b) $b['target'] = 'x' }
    'sequence as a boolean'         = { param($b) $b['sequence'] = $true }
    'null entry'                    = { param($b) $b['entries'][0] = $null }
}
foreach ($name in $mutations.Keys) {
    $b = Get-Body $good
    & $mutations[$name] $b
    Assert-Reason ('format: {0}' -f $name) (Invoke-Validate -Text (Raw-Body $b)) 'FORMAT'
}
$many = Get-Body $good
$template = $many['entries'][0]
$list = [System.Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt 501; $i++) { $copy = [ordered]@{ credentialRef = ('REF' + $i); kind = $template['kind']; wrappedKey = $template['wrappedKey']; nonce = $template['nonce']; ciphertext = $template['ciphertext'] }; $list.Add($copy) }
$many['entries'] = $list.ToArray()
Assert-Reason 'format: 501 entries' (Invoke-Validate -Text (Sign-Body $many)) 'FORMAT'
$many['entries'] = $list.GetRange(0, 500).ToArray()
$bigResult = Invoke-Validate -Text (Sign-Body $many) -Last 4
Assert-That 'format: 500 entries pass the format check (the next check decides)' ($bigResult.Ok -or $bigResult.Reason -cne 'FORMAT')

# ---------------------------------------------------------------------------
# E. An entry cannot be moved to another reference, package or sequence
# ---------------------------------------------------------------------------
$swap = Get-Body $good
foreach ($member in @('wrappedKey', 'nonce', 'ciphertext')) { $t0 = $swap['entries'][0][$member]; $swap['entries'][0][$member] = $swap['entries'][1][$member]; $swap['entries'][1][$member] = $t0 }
$swapResult = Invoke-Validate -Text (Sign-Body $swap)
Assert-That 'move: two entries swapped between references still validate (signed)' $swapResult.Ok
Assert-Throws 'move: the swapped entry no longer decrypts under the first reference' { Get-PackageEntrySecret -Package $swapResult.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyA } 'DECRYPT'
Assert-Throws 'move: the swapped entry no longer decrypts under the second reference' { Get-PackageEntrySecret -Package $swapResult.Package -CredentialRef 'WEB_ACCESS.INST1' -MachineKeyr $keyA } '*'
$otherSequence = Get-Body $good; $otherSequence['sequence'] = [long]9
$osResult = Invoke-Validate -Text (Sign-Body $otherSequence)
Assert-That 'move: the same entries under another sequence validate (signed)' $osResult.Ok
Assert-Throws 'move: ...but do not decrypt (sequence is in the associated data)' { Get-PackageEntrySecret -Package $osResult.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyA } 'DECRYPT'
$otherId = Get-Body $good; $otherId['packageId'] = '00000000-0000-4000-8000-000000000001'
$oiResult = Invoke-Validate -Text (Sign-Body $otherId)
Assert-Throws 'move: the same entries under another package id do not decrypt' { Get-PackageEntrySecret -Package $oiResult.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyA } 'DECRYPT'
$otherServer = Get-Body $good; $otherServer['target']['serverCode'] = 'OTHER_SERVER'
$osvResult = Invoke-Validate -Text (Sign-Body $otherServer) -Server 'OTHER_SERVER'
Assert-Throws 'move: the same entries under another server code do not decrypt' { Get-PackageEntrySecret -Package $osvResult.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyA } 'DECRYPT'
$tamperedPackage = [ordered]@{ target = [ordered]@{ keyFingerprint = $machineB.KeyFingerprint }; entries = $ok.Package['entries']; packageId = $ok.Package['packageId']; sequence = $ok.Package['sequence'] }
Assert-Throws 'move: a package that names another machine key cannot be used with this key' { Get-PackageEntrySecret -Package $tamperedPackage -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $keyA } 'DECRYPT'

# ---------------------------------------------------------------------------
# F. The builder enforces the policy
# ---------------------------------------------------------------------------
function Build { param([hashtable]$Override = @{}) $p = @{ IssuerPrivateKeyPkcs8 = $issuer.PrivateKeyPkcs8; TargetServerCode = $serverCode; TargetMachinePublicKeySpki = $machineA.PublicKeySpki; Sequence = 1; Entries = (New-TestEntries); IssuedAt = $issued }; foreach ($k in $Override.Keys) { $p[$k] = $Override[$k] }; return (New-CredentialPackage @p) }
Assert-That 'build: minimal call works' ((Invoke-Validate -Text (Build) -Last 0).Ok)
Assert-Throws 'build: lifetime of 367 days refused' { Build @{ ExpiresAt = $issued.AddDays(367) } } '*lifetime*'
Assert-That 'build: lifetime of 366 days accepted' ((Invoke-Validate -Text (Build @{ ExpiresAt = $issued.AddDays(366) }) -Last 0).Ok)
Assert-Throws 'build: expiry before issue refused' { Build @{ ExpiresAt = $issued.AddHours(-1) } } '*lifetime*'
Assert-Throws 'build: no entries refused' { Build @{ Entries = @() } } '*'
Assert-Throws 'build: sequence 0 refused' { Build @{ Sequence = 0 } } '*Invalid sequence*'
Assert-Throws 'build: server code with a space refused' { Build @{ TargetServerCode = 'BAD CODE' } } '*server code*'
Assert-Throws 'build: upper-case package id refused' { Build @{ PackageId = '3F2B8C1E-0A4D-4E6B-9C11-5D7E2A9B4F01' } } '*package id*'
Assert-Throws 'build: P-384 machine key refused' { $e = [System.Security.Cryptography.ECDiffieHellman]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384')); Build @{ TargetMachinePublicKeySpki = $e.ExportSubjectPublicKeyInfo() } } '*not an ECDH P-256*'
Assert-Throws 'build: duplicate reference refused' { $e = New-TestEntries; $e[1].CredentialRef = $e[0].CredentialRef; Build @{ Entries = $e } } '*Duplicate*'
Assert-Throws 'build: unknown kind refused' { $e = New-TestEntries; $e[0].Kind = 'OTHER'; Build @{ Entries = $e } } '*kind*'
Assert-Throws 'build: lower-case reference refused' { $e = New-TestEntries; $e[0].CredentialRef = 'iis'; Build @{ Entries = $e } } '*reference*'
Assert-Throws 'build: a text secret (not bytes) refused' { $e = New-TestEntries; $e[0].Secret = 'plain text'; Build @{ Entries = $e } } '*byte array*'
Assert-Throws 'build: empty secret refused' { $e = New-TestEntries; $e[0].Secret = [byte[]]@(); Build @{ Entries = $e } } '*unsupported length*'
Assert-Throws 'build: 501 entries refused' { $e = @(); for ($i = 0; $i -lt 501; $i++) { $e += @{ CredentialRef = ('REF' + $i); Kind = 'RULE_SECRET'; Secret = [byte[]](1, 2, 3) } }; Build @{ Entries = $e } } '*1 to 500*'

# ---------------------------------------------------------------------------
# G. Machine identity text
# ---------------------------------------------------------------------------
$created = [datetime]::new(2026, 10, 5, 8, 30, 0, [System.DateTimeKind]::Utc)
$identity = New-MachineIdentityText -ServerCode $serverCode -MachineName 'TEST-HOST' -PublicKeySpki $machineA.PublicKeySpki -CreatedAt $created
$expected = "-----BEGIN SISQUAL MACHINE IDENTITY-----`nContract: 0.1-proposed`nServerCode: TEST_SERVER`nMachineName: TEST-HOST`nKeyFingerprint: $($machineA.KeyFingerprint)`nKeyAlgorithm: ECDH-P256`nPublicKey: $([Convert]::ToBase64String($machineA.PublicKeySpki))`nCreatedAt: 2026-10-05T08:30:00Z`n-----END SISQUAL MACHINE IDENTITY-----`n"
Assert-That 'identity: text layout (known answer)' ($identity -ceq $expected)
$parsed = ConvertFrom-MachineIdentityText -Text $identity
Assert-That 'identity: round trip' (($parsed.ServerCode -ceq $serverCode) -and ($parsed.MachineName -ceq 'TEST-HOST') -and ($parsed.KeyFingerprint -ceq $machineA.KeyFingerprint) -and ([Convert]::ToHexString($parsed.PublicKeySpki) -ceq [Convert]::ToHexString($machineA.PublicKeySpki)) -and ($parsed.CreatedAt -eq $created))
Assert-That 'identity: a package built from the parsed identity validates' ((Invoke-Validate -Text (New-CredentialPackage -IssuerPrivateKeyPkcs8 $issuer.PrivateKeyPkcs8 -TargetServerCode $parsed.ServerCode -TargetMachinePublicKeySpki $parsed.PublicKeySpki -Sequence 5 -Entries (New-TestEntries) -IssuedAt $issued) -Fingerprint $parsed.KeyFingerprint).Ok)
Assert-That 'identity: CRLF accepted' ((ConvertFrom-MachineIdentityText -Text $identity.Replace("`n", "`r`n")).ServerCode -ceq $serverCode)
Assert-That 'identity: no final line feed accepted' ((ConvertFrom-MachineIdentityText -Text $identity.TrimEnd("`n")).ServerCode -ceq $serverCode)
$identityLines = $identity.TrimEnd("`n").Split("`n")
$p384 = [System.Security.Cryptography.ECDiffieHellman]::Create([System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP384'))
$p384Spki = $p384.ExportSubjectPublicKeyInfo()
$identityCases = [ordered]@{
    'empty'                      = ''
    'missing a line'             = (($identityLines[0..4] + $identityLines[6..8]) -join "`n")
    'lines swapped'              = (($identityLines[0..1] + $identityLines[3] + $identityLines[2] + $identityLines[4..8]) -join "`n")
    'an extra line'              = (($identityLines[0..7] + 'Extra: x' + $identityLines[8]) -join "`n")
    'package armor'              = $identity.Replace('MACHINE IDENTITY', 'CREDENTIAL PACKAGE')
    'text before the armor'      = ("x`n" + $identity)
    'fingerprint of another key' = $identity.Replace($machineA.KeyFingerprint, $machineB.KeyFingerprint)
    'upper-case fingerprint'     = $identity.Replace($machineA.KeyFingerprint, $machineA.KeyFingerprint.ToUpperInvariant())
    'other key algorithm'        = $identity.Replace('ECDH-P256', 'ECDH-P384')
    'public key not base64'      = $identity.Replace($identityLines[6], 'PublicKey: not base64!')
    'public key of another curve' = $identity.Replace($identityLines[6], 'PublicKey: ' + [Convert]::ToBase64String($p384Spki))
    'server code with a space'   = $identity.Replace('TEST_SERVER', 'TEST SERVER')
    'machine name with a space'  = $identity.Replace('TEST-HOST', 'TEST HOST')
    'unknown contract version'   = $identity.Replace('0.1-proposed', '9.9')
    'time without Z'             = $identity.Replace('2026-10-05T08:30:00Z', '2026-10-05T08:30:00')
    'non-ASCII character'        = $identity.Replace('TEST-HOST', 'TEST-H' + [string][char]0xD3 + 'ST')
    'two spaces after a colon'   = $identity.Replace('ServerCode: ', 'ServerCode:  ')
    'too long'                   = ($identity + ('x' * 5000))
}
foreach ($name in $identityCases.Keys) { Assert-Throws ('identity: {0}' -f $name) { ConvertFrom-MachineIdentityText -Text $identityCases[$name] } 'Invalid machine identity text.' }
Assert-Throws 'identity: builder refuses a P-384 key' { New-MachineIdentityText -ServerCode $serverCode -MachineName 'TEST-HOST' -PublicKeySpki $p384Spki } '*not an ECDH P-256*'
Assert-Throws 'identity: builder refuses a server code with a space' { New-MachineIdentityText -ServerCode 'BAD CODE' -MachineName 'TEST-HOST' -PublicKeySpki $machineA.PublicKeySpki } '*Invalid serverCode*'
Assert-Throws 'identity: builder refuses a machine name with a space' { New-MachineIdentityText -ServerCode $serverCode -MachineName 'BAD HOST' -PublicKeySpki $machineA.PublicKeySpki } '*Invalid machineName*'

$keyA.Dispose(); $keyB.Dispose(); $p384.Dispose()
# ---------------------------------------------------------------------------
# Gaps found by mutation testing: format limits, armor, unknown members, fail-closed, duplicate reference
# ---------------------------------------------------------------------------
$goodText = New-GoodPackage
$r = Invoke-Validate -Text ($goodText + ('A' * 262144))
Assert-That 'format: text over 262144 characters fails at check 1 (size)' (($r.Ok -eq $false) -and ($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'size'))
$r = Invoke-Validate -Text ($goodText.TrimEnd("`n") + "`n" + [string][char]0x00E9 + "`n")
Assert-That 'format: a non-ASCII character fails at check 1 (characters)' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'characters'))
$r = Invoke-Validate -Text ($goodText.Replace('-----END', "`t-----END"))
Assert-That 'format: a control character fails at check 1 (characters)' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'characters'))
$r = Invoke-Validate -Text ($goodText.Replace('-----BEGIN SISQUAL CREDENTIAL PACKAGE-----', '-----BEGIN SISQUAL CREDENTIAL PACKAGEX-----'))
Assert-That 'format: a wrong BEGIN armor line fails at check 1 (armor)' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'armor'))
$r = Invoke-Validate -Text ($goodText.Replace('-----END SISQUAL CREDENTIAL PACKAGE-----', '-----END SISQUAL CREDENTIAL PACKAGEX-----'))
Assert-That 'format: a wrong END armor line fails at check 1 (armor)' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'armor'))
$r = Invoke-Validate -Text ("junk`n" + $goodText)
Assert-That 'format: text before the BEGIN line fails at check 1 (armor)' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -ceq 'armor'))
$ub = Get-Body $goodText
$ub['extra'] = 'x'
$r = Invoke-Validate -Text (Sign-Body $ub)
Assert-That 'format: a signed body with an unknown top-level member fails at check 1' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -like '*unknown member*'))
$ub = Get-Body $goodText
$ub['target']['extra'] = 'x'
$r = Invoke-Validate -Text (Sign-Body $ub)
Assert-That 'format: a signed body with an unknown member in target fails at check 1' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -like '*unknown member*'))
$ub = Get-Body $goodText
$ub['entries'][0]['extra'] = 'x'
$r = Invoke-Validate -Text (Sign-Body $ub)
Assert-That 'format: a signed body with an unknown member in an entry fails at check 1' (($r.Reason -ceq 'FORMAT') -and ($r.Detail -like '*unknown member*'))
$r = Test-CredentialPackage -Text $goodText -TrustedIssuerPublicKeySpki $issuer.PublicKeySpki -ServerCode $serverCode -MachineKeyFingerprint $machineA.KeyFingerprint -Now ([datetime]::MaxValue) -LastAcceptedSequence 4
Assert-That 'validate: an unexpected internal error fails closed (FORMAT, nothing returned)' (($r.Ok -eq $false) -and ($r.Reason -ceq 'FORMAT') -and ($null -eq $r.Package))
$liveKey = New-EcdhFromPkcs8 $machineA.PrivateKeyPkcs8
$okResult = Invoke-Validate -Text $goodText
[byte[]]$control = Get-PackageEntrySecret -Package $okResult.Package -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $liveKey
Assert-That 'decrypt: control, the same call works on the unmodified package with a live key' ([System.Text.Encoding]::UTF8.GetString($control) -ceq $markers['IIS_IDENTITY.INST1'])
$dupPackage = $okResult.Package
$dupPackage['entries'] = @($dupPackage['entries'] + $dupPackage['entries'][0])
Assert-Throws 'decrypt: a package object with a duplicated reference is refused' { Get-PackageEntrySecret -Package $dupPackage -CredentialRef 'IIS_IDENTITY.INST1' -MachineKey $liveKey } 'DECRYPT'
$liveKey.Dispose()

Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
