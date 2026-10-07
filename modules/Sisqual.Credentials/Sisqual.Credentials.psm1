#requires -Version 7.0
<#
.SYNOPSIS
    Shared cryptographic helpers of the SISQUAL credential contract (contracts/credential-package.md).

.DESCRIPTION
    Step B6.1a. Used by the credential tool (tools/) and, later, by the portable application.
    The module holds NO key material and writes nothing to disk: keys are passed in by the caller
    and every returned value is a plain object. Nothing here ever writes a secret to any stream.

    Algorithms (owner decision of 2026-10-05, Q2, option A):
      signature   ECDSA P-256 with SHA-256, IEEE P1363 (r || s, 64 bytes)
      entry       ephemeral-static ECDH P-256, HKDF-SHA256, AES-256-GCM
      fingerprint SHA-256 of the DER SubjectPublicKeyInfo, 64 lower-case hex
      canonical   the RFC 8785 subset of tools/Seal-Package.ps1 (verified identical by a unit test)

    Entry layout [PROPOSED, fixed here and covered by tests]:
      wrappedKey  base64 of the ephemeral public key (SubjectPublicKeyInfo)
      nonce       base64 of 12 random bytes
      ciphertext  base64 of (AES-GCM ciphertext || 16-byte tag)
      key         HKDF-SHA256(ikm = ECDH shared secret, salt = SHA-256(ephemeralSpki || machineSpki),
                  info = "SISQUAL credential entry v1", 32 bytes)
      aad         "SISQUAL-CRED-AAD-v1" LF packageId LF serverCode LF keyFingerprint LF credentialRef LF sequence
#>
Set-StrictMode -Version Latest

$script:SignatureAlgorithm = 'ECDSA-P256-SHA256'
$script:AadLabel = 'SISQUAL-CRED-AAD-v1'
$script:HkdfInfoText = 'SISQUAL credential entry v1'
$script:MaxSecretBytes = 8192
$script:P256Oid = '1.2.840.10045.3.1.7'
$script:IssuerKeyBegin = '-----BEGIN SISQUAL ISSUER KEY-----'
$script:IssuerKeyEnd = '-----END SISQUAL ISSUER KEY-----'
$script:IssuerKeyAlgorithm = 'ECDSA-P256'

# ---------------------------------------------------------------------------
# Canonical JSON: the same algorithm as tools/Seal-Package.ps1 (a unit test compares both).
# ---------------------------------------------------------------------------

function ConvertTo-CanonicalString {
    param([string]$Text)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            8 { [void]$sb.Append('\b') }
            9 { [void]$sb.Append('\t') }
            10 { [void]$sb.Append('\n') }
            12 { [void]$sb.Append('\f') }
            13 { [void]$sb.Append('\r') }
            default {
                if ($code -lt 32 -or $code -gt 126) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-CanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-CanonicalString $Value) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return ([long]$Value).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        [string[]]$keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        $parts = foreach ($k in $keys) { (ConvertTo-CanonicalString $k) + ':' + (ConvertTo-CanonicalJson $Value[$k]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        # Ordinal, case-sensitive: keys that differ only by case must never be merged before signing.
        $table = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($p in $Value.PSObject.Properties) { $table[$p.Name] = $p.Value }
        return (ConvertTo-CanonicalJson $table)
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = foreach ($item in $Value) { ConvertTo-CanonicalJson $item }
        return '[' + (@($items) -join ',') + ']'
    }
    throw ('Value of type {0} cannot be written in canonical form.' -f $Value.GetType().FullName)
}

function Get-CanonicalBytes {
    # The canonical bytes of an object, optionally without some top-level members (for example "signature").
    param([Parameter(Mandatory)]$Value, [string[]]$ExcludeMember = @())
    # Ordinal, case-sensitive: keys that differ only by case must never be merged before signing.
    $copy = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    if ($Value -is [System.Collections.IDictionary]) { foreach ($k in $Value.Keys) { $copy[[string]$k] = $Value[$k] } }
    else { foreach ($p in $Value.PSObject.Properties) { $copy[$p.Name] = $p.Value } }
    foreach ($member in $ExcludeMember) { [void]$copy.Remove($member) }
    [byte[]]$bytes = [System.Text.Encoding]::ASCII.GetBytes((ConvertTo-CanonicalJson $copy))
    return , $bytes
}

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Get-Sha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-PublicKeyFingerprint {
    param([Parameter(Mandatory)][byte[]]$PublicKeySpki)
    return (Get-Sha256Hex -Bytes $PublicKeySpki)
}

function ConvertFrom-StrictBase64 {
    # Standard base64 only: no whitespace, correct padding. Throws on anything else.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0 -or ($Text.Length % 4) -ne 0 -or $Text -cnotmatch '^[A-Za-z0-9+/]+={0,2}$') { throw 'Invalid base64.' }
    [byte[]]$bytes = [Convert]::FromBase64String($Text)
    return , $bytes
}

function Join-Bytes {
    param([byte[]]$First, [byte[]]$Second)
    [byte[]]$out = [byte[]]::new($First.Length + $Second.Length)
    [Array]::Copy($First, 0, $out, 0, $First.Length)
    [Array]::Copy($Second, 0, $out, $First.Length, $Second.Length)
    return , $out
}

function Get-MemberValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { if ($Object.Contains($Name)) { return $Object[$Name] } return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Test-P256Key {
    param($Key)
    $curve = $Key.ExportParameters($false).Curve
    if (-not $curve.IsNamed) { return $false }
    $oid = $curve.Oid
    if ($null -eq $oid) { return $false }
    if ($oid.Value -eq $script:P256Oid) { return $true }
    return ([string]$oid.FriendlyName -in @('nistP256', 'ECDSA_P256', 'ECDH_P256', 'P-256'))
}

# ---------------------------------------------------------------------------
# Keys. The module never stores a key; the caller owns and protects the bytes.
# ---------------------------------------------------------------------------

function New-IssuerKeyMaterial {
    # A new ECDSA P-256 issuer key pair. The caller must protect PrivateKeyPkcs8 (the vault does).
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256')
    $key = [System.Security.Cryptography.ECDsa]::Create($curve)
    try {
        [byte[]]$private = $key.ExportPkcs8PrivateKey()
        [byte[]]$public = $key.ExportSubjectPublicKeyInfo()
        return [ordered]@{ PrivateKeyPkcs8 = $private; PublicKeySpki = $public; KeyId = (Get-PublicKeyFingerprint -PublicKeySpki $public) }
    }
    finally { $key.Dispose() }
}

function New-EcdhKeyMaterial {
    # An ECDH P-256 key pair. Meant for tests and development: the real machine key is created by the
    # application and kept non-exportable (Phase 1B).
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256')
    $key = [System.Security.Cryptography.ECDiffieHellman]::Create($curve)
    try {
        [byte[]]$private = $key.ExportPkcs8PrivateKey()
        [byte[]]$public = $key.ExportSubjectPublicKeyInfo()
        return [ordered]@{ PrivateKeyPkcs8 = $private; PublicKeySpki = $public; KeyFingerprint = (Get-PublicKeyFingerprint -PublicKeySpki $public) }
    }
    finally { $key.Dispose() }
}

# ---------------------------------------------------------------------------
# Signature: ECDSA P-256 / SHA-256
# ---------------------------------------------------------------------------

function New-IssuerSignature {
    # Returns { issuerKeyId, algorithm, value }, the shape tools/Seal-Package.ps1 expects from a signer.
    param([Parameter(Mandatory)][byte[]]$PrivateKeyPkcs8, [Parameter(Mandatory)][byte[]]$Data)
    $key = [System.Security.Cryptography.ECDsa]::Create()
    try {
        $read = 0
        $key.ImportPkcs8PrivateKey($PrivateKeyPkcs8, [ref]$read)
        if (-not (Test-P256Key $key)) { throw 'The issuer key is not an ECDSA P-256 key.' }
        [byte[]]$public = $key.ExportSubjectPublicKeyInfo()
        [byte[]]$signature = $key.SignData($Data, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        return [ordered]@{
            issuerKeyId = (Get-PublicKeyFingerprint -PublicKeySpki $public)
            algorithm   = $script:SignatureAlgorithm
            value       = [Convert]::ToBase64String($signature)
        }
    }
    finally { $key.Dispose() }
}

function Test-IssuerSignature {
    # True only when the algorithm, the key id and the signature all match. Never throws.
    param([byte[]]$PublicKeySpki, [byte[]]$Data, $Signature)
    try {
        if ($null -eq $PublicKeySpki -or $null -eq $Data -or $null -eq $Signature) { return $false }
        if ([string](Get-MemberValue $Signature 'algorithm') -cne $script:SignatureAlgorithm) { return $false }
        if ([string](Get-MemberValue $Signature 'issuerKeyId') -cne (Get-PublicKeyFingerprint -PublicKeySpki $PublicKeySpki)) { return $false }
        [byte[]]$raw = ConvertFrom-StrictBase64 -Text ([string](Get-MemberValue $Signature 'value'))
        if ($raw.Length -ne 64) { return $false }
        $key = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $read = 0
            $key.ImportSubjectPublicKeyInfo($PublicKeySpki, [ref]$read)
            if ($read -ne $PublicKeySpki.Length -or -not (Test-P256Key $key)) { return $false }
            return [bool]$key.VerifyData($Data, $raw, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        }
        finally { $key.Dispose() }
    }
    catch { return $false }
}

# ---------------------------------------------------------------------------
# Credential entries: ECDH-ES (P-256) + HKDF-SHA256 + AES-256-GCM
# ---------------------------------------------------------------------------

function Get-EntryAad {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$ServerCode,
        [Parameter(Mandatory)][string]$KeyFingerprint,
        [Parameter(Mandatory)][string]$CredentialRef,
        [Parameter(Mandatory)][long]$Sequence
    )
    if ($PackageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'Invalid packageId.' }
    if ($ServerCode -cnotmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'Invalid serverCode.' }
    if ($KeyFingerprint -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid keyFingerprint.' }
    if ($CredentialRef -cnotmatch '^[A-Z0-9_.:-]{1,120}$') { throw 'Invalid credentialRef.' }
    if ($Sequence -lt 1) { throw 'Invalid sequence.' }
    $text = $script:AadLabel + "`n" + $PackageId + "`n" + $ServerCode + "`n" + $KeyFingerprint + "`n" + $CredentialRef + "`n" + $Sequence.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [byte[]]$bytes = [System.Text.Encoding]::ASCII.GetBytes($text)
    return , $bytes
}

function Get-EntryContentKey {
    # HKDF-SHA256 over the ECDH shared secret; the salt binds both public keys.
    param([byte[]]$SharedSecret, [byte[]]$EphemeralSpki, [byte[]]$MachineSpki)
    [byte[]]$salt = [System.Security.Cryptography.SHA256]::HashData((Join-Bytes $EphemeralSpki $MachineSpki))
    [byte[]]$info = [System.Text.Encoding]::ASCII.GetBytes($script:HkdfInfoText)
    [byte[]]$key = [System.Security.Cryptography.HKDF]::DeriveKey([System.Security.Cryptography.HashAlgorithmName]::SHA256, $SharedSecret, 32, $salt, $info)
    return , $key
}

function Protect-CredentialEntry {
    # Encrypts one secret for one machine public key. The secret is a byte array owned by the caller.
    param(
        [Parameter(Mandatory)][byte[]]$MachinePublicKeySpki,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Secret,
        [Parameter(Mandatory)][byte[]]$Aad
    )
    if ($Secret.Length -lt 1 -or $Secret.Length -gt $script:MaxSecretBytes) { throw 'The secret has an unsupported length.' }
    $curve = [System.Security.Cryptography.ECCurve]::CreateFromFriendlyName('nistP256')
    $machine = [System.Security.Cryptography.ECDiffieHellman]::Create()
    $ephemeral = [System.Security.Cryptography.ECDiffieHellman]::Create($curve)
    $shared = $null
    $key = $null
    try {
        $read = 0
        $machine.ImportSubjectPublicKeyInfo($MachinePublicKeySpki, [ref]$read)
        if ($read -ne $MachinePublicKeySpki.Length -or -not (Test-P256Key $machine)) { throw 'The machine public key is not an ECDH P-256 key.' }
        [byte[]]$ephemeralSpki = $ephemeral.ExportSubjectPublicKeyInfo()
        $shared = $ephemeral.DeriveRawSecretAgreement($machine.PublicKey)
        $key = Get-EntryContentKey -SharedSecret $shared -EphemeralSpki $ephemeralSpki -MachineSpki $MachinePublicKeySpki
        [byte[]]$nonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
        [byte[]]$cipher = [byte[]]::new($Secret.Length)
        [byte[]]$tag = [byte[]]::new(16)
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        try { $aes.Encrypt($nonce, $Secret, $cipher, $tag, $Aad) } finally { $aes.Dispose() }
        return [ordered]@{
            wrappedKey = [Convert]::ToBase64String($ephemeralSpki)
            nonce      = [Convert]::ToBase64String($nonce)
            ciphertext = [Convert]::ToBase64String((Join-Bytes $cipher $tag))
        }
    }
    finally {
        if ($null -ne $shared) { [Array]::Clear($shared, 0, $shared.Length) }
        if ($null -ne $key) { [Array]::Clear($key, 0, $key.Length) }
        $machine.Dispose()
        $ephemeral.Dispose()
    }
}

function Unprotect-CredentialEntry {
    # Decrypts one entry with the machine private key (an ECDiffieHellman object, so a non-exportable
    # CNG key can be used). Any failure is the same generic error: the reason is never detailed.
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellman]$MachineKey,
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][byte[]]$Aad
    )
    $shared = $null
    $key = $null
    $ephemeral = [System.Security.Cryptography.ECDiffieHellman]::Create()
    try {
        [byte[]]$ephemeralSpki = ConvertFrom-StrictBase64 -Text ([string](Get-MemberValue $Entry 'wrappedKey'))
        [byte[]]$nonce = ConvertFrom-StrictBase64 -Text ([string](Get-MemberValue $Entry 'nonce'))
        [byte[]]$sealed = ConvertFrom-StrictBase64 -Text ([string](Get-MemberValue $Entry 'ciphertext'))
        if ($nonce.Length -ne 12 -or $sealed.Length -lt 17 -or $sealed.Length -gt ($script:MaxSecretBytes + 16)) { throw 'DECRYPT' }
        $read = 0
        $ephemeral.ImportSubjectPublicKeyInfo($ephemeralSpki, [ref]$read)
        if ($read -ne $ephemeralSpki.Length -or -not (Test-P256Key $ephemeral)) { throw 'DECRYPT' }
        [byte[]]$machineSpki = $MachineKey.ExportSubjectPublicKeyInfo()
        $shared = $MachineKey.DeriveRawSecretAgreement($ephemeral.PublicKey)
        $key = Get-EntryContentKey -SharedSecret $shared -EphemeralSpki $ephemeralSpki -MachineSpki $machineSpki
        $length = $sealed.Length - 16
        [byte[]]$cipher = [byte[]]::new($length)
        [byte[]]$tag = [byte[]]::new(16)
        [Array]::Copy($sealed, 0, $cipher, 0, $length)
        [Array]::Copy($sealed, $length, $tag, 0, 16)
        [byte[]]$plain = [byte[]]::new($length)
        $aes = [System.Security.Cryptography.AesGcm]::new($key, 16)
        try { $aes.Decrypt($nonce, $cipher, $tag, $plain, $Aad) } finally { $aes.Dispose() }
        return , $plain
    }
    catch { throw 'DECRYPT' }
    finally {
        if ($null -ne $shared) { [Array]::Clear($shared, 0, $shared.Length) }
        if ($null -ne $key) { [Array]::Clear($key, 0, $key.Length) }
        $ephemeral.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Machine identity text, credential package and its validation
# (contracts/credential-package.md sections 3a, 4 and 6)
# ---------------------------------------------------------------------------

$script:ContractVersion = '0.1-proposed'
$script:SupportedContractVersions = @('0.1-proposed')
$script:MaxPackageChars = 262144
$script:MaxLifetimeDays = 366
$script:MaxSkewMinutes = 15
$script:PackageBegin = '-----BEGIN SISQUAL CREDENTIAL PACKAGE-----'
$script:PackageEnd = '-----END SISQUAL CREDENTIAL PACKAGE-----'
$script:IdentityBegin = '-----BEGIN SISQUAL MACHINE IDENTITY-----'
$script:IdentityEnd = '-----END SISQUAL MACHINE IDENTITY-----'
$script:KeyWrapId = 'ECDH-ES-P256-HKDF-SHA256'
$script:ContentId = 'AES-256-GCM'
$script:IdentityKeyAlgorithm = 'ECDH-P256'
$script:EntryKinds = @('IIS_IDENTITY', 'WEB_ACCESS', 'MOBILE_APP_TOKEN', 'RULE_SECRET')
$script:TimeFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

function Test-EcdhPublicKeySpki {
    param([byte[]]$Spki)
    $key = [System.Security.Cryptography.ECDiffieHellman]::Create()
    try {
        $read = 0
        $key.ImportSubjectPublicKeyInfo($Spki, [ref]$read)
        return (($read -eq $Spki.Length) -and (Test-P256Key $key))
    }
    catch { return $false }
    finally { $key.Dispose() }
}

function ConvertTo-UtcTimeText {
    param([datetime]$Time)
    return $Time.ToUniversalTime().ToString($script:TimeFormat, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-UtcTimeText {
    param([string]$Text)
    if ($Text -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { throw 'Invalid time.' }
    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
    return [datetime]::ParseExact($Text, $script:TimeFormat, [System.Globalization.CultureInfo]::InvariantCulture, $styles)
}

# --- machine identity text (contract section 3a) -----------------------------

function New-MachineIdentityText {
    # The text the application shows on the target machine; the operator carries it to the credential tool.
    param(
        [Parameter(Mandatory)][string]$ServerCode,
        [Parameter(Mandatory)][string]$MachineName,
        [Parameter(Mandatory)][byte[]]$PublicKeySpki,
        [datetime]$CreatedAt = [datetime]::UtcNow
    )
    if ($ServerCode -cnotmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'Invalid serverCode.' }
    if ($MachineName -cnotmatch '^[A-Za-z0-9._-]{1,63}$') { throw 'Invalid machineName.' }
    if (-not (Test-EcdhPublicKeySpki $PublicKeySpki)) { throw 'The public key is not an ECDH P-256 key.' }
    $lines = @(
        $script:IdentityBegin,
        ('Contract: ' + $script:ContractVersion),
        ('ServerCode: ' + $ServerCode),
        ('MachineName: ' + $MachineName),
        ('KeyFingerprint: ' + (Get-PublicKeyFingerprint -PublicKeySpki $PublicKeySpki)),
        ('KeyAlgorithm: ' + $script:IdentityKeyAlgorithm),
        ('PublicKey: ' + [Convert]::ToBase64String($PublicKeySpki)),
        ('CreatedAt: ' + (ConvertTo-UtcTimeText $CreatedAt)),
        $script:IdentityEnd
    )
    return (($lines -join "`n") + "`n")
}

function ConvertFrom-MachineIdentityText {
    # Strict parser. Any problem is the same generic error: the text comes from another machine.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    try {
        if ($Text.Length -eq 0 -or $Text.Length -gt 4096 -or $Text -cmatch '[^\x0A\x0D\x20-\x7E]') { throw 'x' }
        $normalized = $Text.Replace("`r`n", "`n")
        if ($normalized.Contains("`r")) { throw 'x' }
        $lines = [System.Collections.Generic.List[string]]::new($normalized.Split("`n"))
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -eq 0) { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -ne 9 -or $lines[0] -cne $script:IdentityBegin -or $lines[8] -cne $script:IdentityEnd) { throw 'x' }
        $names = @('Contract', 'ServerCode', 'MachineName', 'KeyFingerprint', 'KeyAlgorithm', 'PublicKey', 'CreatedAt')
        $values = @{}
        for ($i = 0; $i -lt 7; $i++) {
            $prefix = $names[$i] + ': '
            if (-not $lines[$i + 1].StartsWith($prefix, [System.StringComparison]::Ordinal)) { throw 'x' }
            $values[$names[$i]] = $lines[$i + 1].Substring($prefix.Length)
        }
        if ($values['Contract'] -cnotin $script:SupportedContractVersions) { throw 'x' }
        if ($values['ServerCode'] -cnotmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'x' }
        if ($values['MachineName'] -cnotmatch '^[A-Za-z0-9._-]{1,63}$') { throw 'x' }
        if ($values['KeyAlgorithm'] -cne $script:IdentityKeyAlgorithm) { throw 'x' }
        [byte[]]$spki = ConvertFrom-StrictBase64 -Text $values['PublicKey']
        if (-not (Test-EcdhPublicKeySpki $spki)) { throw 'x' }
        if ($values['KeyFingerprint'] -cne (Get-PublicKeyFingerprint -PublicKeySpki $spki)) { throw 'x' }
        $created = ConvertFrom-UtcTimeText $values['CreatedAt']
        return [ordered]@{
            ServerCode     = $values['ServerCode']
            MachineName    = $values['MachineName']
            KeyFingerprint = $values['KeyFingerprint']
            PublicKeySpki  = $spki
            CreatedAt      = $created
        }
    }
    catch { throw 'Invalid machine identity text.' }
}

# --- package body: JSON reading with System.Text.Json (no date conversion, duplicate members refused) ----

function Stop-Format {
    param([string]$Detail)
    throw ('FORMAT:' + $Detail)
}

function ConvertFrom-JsonElement {
    param([System.Text.Json.JsonElement]$Element, [int]$Depth = 0)
    if ($Depth -gt 10) { Stop-Format 'nesting' }
    $kind = $Element.ValueKind
    if ($kind -eq [System.Text.Json.JsonValueKind]::Object) {
        $table = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if ($table.Contains($property.Name)) { Stop-Format 'duplicate member' }
            $table[$property.Name] = ConvertFrom-JsonElement -Element $property.Value -Depth ($Depth + 1)
        }
        return $table
    }
    if ($kind -eq [System.Text.Json.JsonValueKind]::Array) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Element.EnumerateArray()) { $list.Add((ConvertFrom-JsonElement -Element $item -Depth ($Depth + 1))) }
        return , $list.ToArray()
    }
    if ($kind -eq [System.Text.Json.JsonValueKind]::String) { return $Element.GetString() }
    if ($kind -eq [System.Text.Json.JsonValueKind]::Number) {
        $number = 0L
        if (-not $Element.TryGetInt64([ref]$number)) { Stop-Format 'number' }
        return $number
    }
    if ($kind -eq [System.Text.Json.JsonValueKind]::True) { return $true }
    if ($kind -eq [System.Text.Json.JsonValueKind]::False) { return $false }
    return $null
}

function Assert-Members {
    param($Object, [string[]]$Required, [string[]]$Optional = @(), [string]$Path)
    if ($Object -isnot [System.Collections.IDictionary]) { Stop-Format ($Path + ' is not an object') }
    $names = @($Object.Keys | ForEach-Object { [string]$_ })
    foreach ($name in $names) {
        if (($Required -cnotcontains $name) -and ($Optional -cnotcontains $name)) { Stop-Format ($Path + ' has an unknown member') }
    }
    foreach ($name in $Required) {
        if ($names -cnotcontains $name) { Stop-Format ($Path + '.' + $name + ' is missing') }
    }
}

function Assert-TextField {
    param($Object, [string]$Name, [string]$Pattern, [string]$Path)
    $value = $Object[$Name]
    if ($value -isnot [string] -or $value -cnotmatch $Pattern) { Stop-Format ($Path + '.' + $Name) }
}

function ConvertFrom-PackageText {
    # Check 1 of contract section 6: armor, ASCII, size, base64, JSON, members and field formats.
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -gt $script:MaxPackageChars) { Stop-Format 'size' }
    if ($Text -cmatch '[^\x0A\x0D\x20-\x7E]') { Stop-Format 'characters' }
    $normalized = $Text.Replace("`r`n", "`n")
    if ($normalized.Contains("`r")) { Stop-Format 'line endings' }
    $lines = [System.Collections.Generic.List[string]]::new($normalized.Split("`n"))
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -eq 0) { $lines.RemoveAt($lines.Count - 1) }
    if ($lines.Count -lt 3 -or $lines[0] -cne $script:PackageBegin -or $lines[$lines.Count - 1] -cne $script:PackageEnd) { Stop-Format 'armor' }
    $payload = [System.Text.StringBuilder]::new()
    for ($i = 1; $i -lt ($lines.Count - 1); $i++) {
        if ($lines[$i] -cnotmatch '^[A-Za-z0-9+/]{1,76}={0,2}$') { Stop-Format 'body line' }
        [void]$payload.Append($lines[$i])
    }
    try { [byte[]]$jsonBytes = ConvertFrom-StrictBase64 -Text $payload.ToString() } catch { Stop-Format 'base64' }
    $json = [System.Text.Encoding]::UTF8.GetString($jsonBytes)
    if ($json -cmatch '[^\x09\x0A\x0D\x20-\x7E]') { Stop-Format 'body characters' }
    $options = [System.Text.Json.JsonDocumentOptions]@{ MaxDepth = 12 }
    try { $document = [System.Text.Json.JsonDocument]::Parse($json, $options) } catch { Stop-Format 'json' }
    try { $body = ConvertFrom-JsonElement -Element $document.RootElement } finally { $document.Dispose() }

    Assert-Members $body @('contractVersion', 'packageId', 'sequence', 'issuedAt', 'expiresAt', 'issuer', 'target', 'encryption', 'entries', 'signature') @('notBefore') 'package'
    Assert-TextField $body 'contractVersion' '^[0-9A-Za-z._-]{1,32}$' 'package'
    Assert-TextField $body 'packageId' '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' 'package'
    if ($body['sequence'] -isnot [long] -or $body['sequence'] -lt 1) { Stop-Format 'package.sequence' }
    foreach ($name in @('issuedAt', 'expiresAt', 'notBefore')) {
        if ($body.Contains($name)) {
            Assert-TextField $body $name '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' 'package'
            try { [void](ConvertFrom-UtcTimeText $body[$name]) } catch { Stop-Format ('package.' + $name) }
        }
    }
    Assert-Members $body['issuer'] @('keyId') @() 'issuer'
    Assert-TextField $body['issuer'] 'keyId' '^[0-9a-f]{64}$' 'issuer'
    Assert-Members $body['target'] @('serverCode', 'keyFingerprint') @('machineName') 'target'
    Assert-TextField $body['target'] 'serverCode' '^[A-Za-z0-9_-]{1,60}$' 'target'
    Assert-TextField $body['target'] 'keyFingerprint' '^[0-9a-f]{64}$' 'target'
    if ($body['target'].Contains('machineName')) { Assert-TextField $body['target'] 'machineName' '^[A-Za-z0-9._-]{1,63}$' 'target' }
    Assert-Members $body['encryption'] @('keyWrap', 'content') @() 'encryption'
    Assert-TextField $body['encryption'] 'keyWrap' '^[A-Za-z0-9._+-]{3,40}$' 'encryption'
    Assert-TextField $body['encryption'] 'content' '^[A-Za-z0-9._+-]{3,40}$' 'encryption'
    Assert-Members $body['signature'] @('algorithm', 'value') @() 'signature'
    Assert-TextField $body['signature'] 'algorithm' '^[A-Za-z0-9._+-]{3,40}$' 'signature'
    Assert-TextField $body['signature'] 'value' '^[A-Za-z0-9+/]{16,2048}={0,2}$' 'signature'
    $entries = $body['entries']
    if ($entries -isnot [object[]] -or $entries.Count -lt 1 -or $entries.Count -gt 500) { Stop-Format 'package.entries' }
    $index = 0
    foreach ($entry in $entries) {
        $path = 'entries[' + $index + ']'
        Assert-Members $entry @('credentialRef', 'kind', 'wrappedKey', 'nonce', 'ciphertext') @('instanceCode') $path
        Assert-TextField $entry 'credentialRef' '^[A-Z0-9_.:-]{1,120}$' $path
        if ($entry['kind'] -isnot [string] -or $script:EntryKinds -cnotcontains $entry['kind']) { Stop-Format ($path + '.kind') }
        if ($entry.Contains('instanceCode')) { Assert-TextField $entry 'instanceCode' '^[A-Za-z0-9_-]{1,60}$' $path }
        foreach ($name in @('wrappedKey', 'nonce', 'ciphertext')) { Assert-TextField $entry $name '^[A-Za-z0-9+/]{4,12000}={0,2}$' $path }
        try {
            $wrapped = ConvertFrom-StrictBase64 -Text $entry['wrappedKey']
            $nonce = ConvertFrom-StrictBase64 -Text $entry['nonce']
            $sealed = ConvertFrom-StrictBase64 -Text $entry['ciphertext']
        }
        catch { Stop-Format ($path + ' base64') }
        if ($wrapped.Length -ne 91 -or $nonce.Length -ne 12 -or $sealed.Length -lt 17 -or $sealed.Length -gt ($script:MaxSecretBytes + 16)) { Stop-Format ($path + ' sizes') }
        $index++
    }
    return $body
}

function New-SignedPackageText {
    # Internal: signs any body and armors it. The exported builder enforces the policy before calling this;
    # the unit tests call it to build packages that break the policy on purpose.
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Body, [Parameter(Mandatory)][byte[]]$IssuerPrivateKeyPkcs8)
    [byte[]]$canonical = Get-CanonicalBytes -Value $Body -ExcludeMember @('signature')
    $signature = New-IssuerSignature -PrivateKeyPkcs8 $IssuerPrivateKeyPkcs8 -Data $canonical
    $signed = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
    foreach ($key in $Body.Keys) { if ([string]$key -cne 'signature') { $signed[[string]$key] = $Body[$key] } }
    $signed['signature'] = [ordered]@{ algorithm = $signature.algorithm; value = $signature.value }
    return (ConvertTo-PackageArmor -JsonBytes ([System.Text.Encoding]::ASCII.GetBytes((ConvertTo-CanonicalJson $signed))))
}

function ConvertTo-PackageArmor {
    param([byte[]]$JsonBytes)
    $text = [Convert]::ToBase64String($JsonBytes)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($script:PackageBegin)
    for ($i = 0; $i -lt $text.Length; $i += 76) { $lines.Add($text.Substring($i, [Math]::Min(76, $text.Length - $i))) }
    $lines.Add($script:PackageEnd)
    return (($lines -join "`n") + "`n")
}

function Get-IssuerPublicKeySpki {
    param([Parameter(Mandatory)][byte[]]$PrivateKeyPkcs8)
    $key = [System.Security.Cryptography.ECDsa]::Create()
    try {
        $read = 0
        $key.ImportPkcs8PrivateKey($PrivateKeyPkcs8, [ref]$read)
        if (-not (Test-P256Key $key)) { throw 'The issuer key is not an ECDSA P-256 key.' }
        [byte[]]$spki = $key.ExportSubjectPublicKeyInfo()
        return , $spki
    }
    finally { $key.Dispose() }
}

function New-CredentialPackage {
    # Builds the text package for ONE machine. Each entry of -Entries is a hashtable with
    # CredentialRef, Kind, Secret (byte[]) and optionally InstanceCode. Returns the package text.
    param(
        [Parameter(Mandatory)][byte[]]$IssuerPrivateKeyPkcs8,
        [Parameter(Mandatory)][string]$TargetServerCode,
        [Parameter(Mandatory)][byte[]]$TargetMachinePublicKeySpki,
        [string]$TargetMachineName,
        [Parameter(Mandatory)][long]$Sequence,
        [Parameter(Mandatory)][object[]]$Entries,
        [datetime]$IssuedAt = [datetime]::UtcNow,
        [datetime]$ExpiresAt,
        [datetime]$NotBefore,
        [string]$PackageId = [guid]::NewGuid().ToString()
    )
    if ($TargetServerCode -cnotmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'Invalid target server code.' }
    if ($PSBoundParameters.ContainsKey('TargetMachineName') -and $TargetMachineName -cnotmatch '^[A-Za-z0-9._-]{1,63}$') { throw 'Invalid target machine name.' }
    if ($Sequence -lt 1) { throw 'Invalid sequence.' }
    if ($PackageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'Invalid package id.' }
    if (-not (Test-EcdhPublicKeySpki $TargetMachinePublicKeySpki)) { throw 'The machine public key is not an ECDH P-256 key.' }
    $issued = (ConvertFrom-UtcTimeText (ConvertTo-UtcTimeText $IssuedAt))
    $expires = if ($PSBoundParameters.ContainsKey('ExpiresAt')) { ConvertFrom-UtcTimeText (ConvertTo-UtcTimeText $ExpiresAt) } else { $issued.AddDays(365) }
    if ($expires -le $issued -or ($expires - $issued).TotalDays -gt $script:MaxLifetimeDays) { throw 'The package lifetime must be positive and at most one year.' }
    if ($Entries.Count -lt 1 -or $Entries.Count -gt 500) { throw 'A package needs 1 to 500 entries.' }
    [byte[]]$issuerSpki = Get-IssuerPublicKeySpki -PrivateKeyPkcs8 $IssuerPrivateKeyPkcs8
    $targetFingerprint = Get-PublicKeyFingerprint -PublicKeySpki $TargetMachinePublicKeySpki
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $built = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Entries) {
        $ref = [string](Get-MemberValue $item 'CredentialRef')
        $kind = [string](Get-MemberValue $item 'Kind')
        $instance = Get-MemberValue $item 'InstanceCode'
        # Read by direct assignment: a function would unroll the byte[] into object[].
        $secret = $null
        if ($item -is [System.Collections.IDictionary]) { if ($item.Contains('Secret')) { $secret = $item['Secret'] } }
        else { $property = $item.PSObject.Properties['Secret']; if ($null -ne $property) { $secret = $property.Value } }
        if ($ref -cnotmatch '^[A-Z0-9_.:-]{1,120}$') { throw 'Invalid credential reference.' }
        if ($script:EntryKinds -cnotcontains $kind) { throw 'Invalid credential kind.' }
        if (-not $seen.Add($ref)) { throw 'Duplicate credential reference.' }
        if ($null -ne $instance -and ([string]$instance) -cnotmatch '^[A-Za-z0-9_-]{1,60}$') { throw 'Invalid instance code.' }
        if ($secret -isnot [byte[]]) { throw 'The secret must be a byte array.' }
        [byte[]]$aad = Get-EntryAad -PackageId $PackageId -ServerCode $TargetServerCode -KeyFingerprint $targetFingerprint -CredentialRef $ref -Sequence $Sequence
        $sealed = Protect-CredentialEntry -MachinePublicKeySpki $TargetMachinePublicKeySpki -Secret $secret -Aad $aad
        $entry = [ordered]@{ credentialRef = $ref; kind = $kind }
        if ($null -ne $instance) { $entry['instanceCode'] = [string]$instance }
        $entry['wrappedKey'] = $sealed['wrappedKey']
        $entry['nonce'] = $sealed['nonce']
        $entry['ciphertext'] = $sealed['ciphertext']
        $built.Add($entry)
    }
    $target = [ordered]@{ serverCode = $TargetServerCode; keyFingerprint = $targetFingerprint }
    if ($PSBoundParameters.ContainsKey('TargetMachineName')) { $target['machineName'] = $TargetMachineName }
    $body = [ordered]@{ contractVersion = $script:ContractVersion; packageId = $PackageId; sequence = $Sequence; issuedAt = (ConvertTo-UtcTimeText $issued) }
    if ($PSBoundParameters.ContainsKey('NotBefore')) { $body['notBefore'] = (ConvertTo-UtcTimeText $NotBefore) }
    $body['expiresAt'] = (ConvertTo-UtcTimeText $expires)
    $body['issuer'] = [ordered]@{ keyId = (Get-PublicKeyFingerprint -PublicKeySpki $issuerSpki) }
    $body['target'] = $target
    $body['encryption'] = [ordered]@{ keyWrap = $script:KeyWrapId; content = $script:ContentId }
    $body['entries'] = $built.ToArray()
    return (New-SignedPackageText -Body $body -IssuerPrivateKeyPkcs8 $IssuerPrivateKeyPkcs8)
}

function Test-CredentialPackage {
    # The eight checks of contract section 6, in order; stops at the first failure and decrypts nothing.
    # Returns Ok, Reason (FORMAT, VERSION, SIGNATURE, TARGET_SERVER, TARGET_KEY, TIME_WINDOW, REPLAY,
    # DUPLICATE_REF), Detail (a field path, never a value) and, when Ok, the validated Package.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][byte[]]$TrustedIssuerPublicKeySpki,
        [Parameter(Mandatory)][string]$ServerCode,
        [Parameter(Mandatory)][string]$MachineKeyFingerprint,
        [datetime]$Now = [datetime]::UtcNow,
        [long]$LastAcceptedSequence = 0,
        [string[]]$SupportedContractVersions = $script:SupportedContractVersions
    )
    $fail = { param($reason, $detail) return [ordered]@{ Ok = $false; Reason = $reason; Detail = $detail; Package = $null } }
    try {
        try { $body = ConvertFrom-PackageText -Text $Text }
        catch {
            $message = [string]$_.Exception.Message
            $detail = if ($message.StartsWith('FORMAT:', [System.StringComparison]::Ordinal)) { $message.Substring(7) } else { 'unexpected' }
            return (& $fail 'FORMAT' $detail)
        }
        if ($SupportedContractVersions -cnotcontains $body['contractVersion'] -or $body['encryption']['keyWrap'] -cne $script:KeyWrapId -or $body['encryption']['content'] -cne $script:ContentId) { return (& $fail 'VERSION' 'contractVersion') }
        [byte[]]$canonical = Get-CanonicalBytes -Value $body -ExcludeMember @('signature')
        $signature = [ordered]@{ issuerKeyId = $body['issuer']['keyId']; algorithm = $body['signature']['algorithm']; value = $body['signature']['value'] }
        if (-not (Test-IssuerSignature -PublicKeySpki $TrustedIssuerPublicKeySpki -Data $canonical -Signature $signature)) { return (& $fail 'SIGNATURE' 'signature') }
        if ($body['target']['serverCode'] -cne $ServerCode) { return (& $fail 'TARGET_SERVER' 'target.serverCode') }
        if ($body['target']['keyFingerprint'] -cne $MachineKeyFingerprint) { return (& $fail 'TARGET_KEY' 'target.keyFingerprint') }
        $utcNow = $Now.ToUniversalTime()
        $issued = ConvertFrom-UtcTimeText $body['issuedAt']
        $expires = ConvertFrom-UtcTimeText $body['expiresAt']
        if ($issued -gt $utcNow.AddMinutes($script:MaxSkewMinutes)) { return (& $fail 'TIME_WINDOW' 'issuedAt') }
        if ($body.Contains('notBefore') -and (ConvertFrom-UtcTimeText $body['notBefore']) -gt $utcNow) { return (& $fail 'TIME_WINDOW' 'notBefore') }
        if ($utcNow -gt $expires) { return (& $fail 'TIME_WINDOW' 'expiresAt') }
        if ($expires -le $issued -or ($expires - $issued).TotalDays -gt $script:MaxLifetimeDays) { return (& $fail 'TIME_WINDOW' 'lifetime') }
        if ($body['sequence'] -le $LastAcceptedSequence) { return (& $fail 'REPLAY' 'sequence') }
        $refs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $body['entries']) { if (-not $refs.Add([string]$entry['credentialRef'])) { return (& $fail 'DUPLICATE_REF' 'entries') } }
        return [ordered]@{ Ok = $true; Reason = $null; Detail = $null; Package = $body }
    }
    catch { return (& $fail 'FORMAT' 'unexpected') }
}

function Get-PackageEntrySecret {
    # Decrypts one entry of a package that Test-CredentialPackage accepted, in memory, with the machine key.
    param(
        [Parameter(Mandatory)]$Package,
        [Parameter(Mandatory)][string]$CredentialRef,
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellman]$MachineKey
    )
    try {
        [byte[]]$spki = $MachineKey.ExportSubjectPublicKeyInfo()
        if ((Get-PublicKeyFingerprint -PublicKeySpki $spki) -cne [string]$Package['target']['keyFingerprint']) { throw 'x' }
        $found = @($Package['entries'] | Where-Object { [string]$_['credentialRef'] -ceq $CredentialRef })
        if ($found.Count -ne 1) { throw 'x' }
        [byte[]]$aad = Get-EntryAad -PackageId ([string]$Package['packageId']) -ServerCode ([string]$Package['target']['serverCode']) -KeyFingerprint ([string]$Package['target']['keyFingerprint']) -CredentialRef $CredentialRef -Sequence ([long]$Package['sequence'])
        [byte[]]$plain = Unprotect-CredentialEntry -MachineKey $MachineKey -Entry $found[0] -Aad $aad
        return , $plain
    }
    catch { throw 'DECRYPT' }
}


# ---------------------------------------------------------------------------
# Issuer public key text (B6.2b): what the operator pins on a machine after comparing the fingerprint
# ---------------------------------------------------------------------------

function Test-EcdsaPublicKeySpki {
    param([byte[]]$Spki)
    try {
        $key = [System.Security.Cryptography.ECDsa]::Create()
        try {
            $read = 0
            $key.ImportSubjectPublicKeyInfo($Spki, [ref]$read)
            return ($read -eq $Spki.Length -and (Test-P256Key $key))
        }
        finally { $key.Dispose() }
    }
    catch { return $false }
}

function New-IssuerPublicKeyText {
    param([Parameter(Mandatory)][byte[]]$PublicKeySpki)
    if (-not (Test-EcdsaPublicKeySpki $PublicKeySpki)) { throw 'The public key is not an ECDSA P-256 key.' }
    $lines = @(
        $script:IssuerKeyBegin,
        ('Contract: ' + $script:ContractVersion),
        ('KeyId: ' + (Get-PublicKeyFingerprint -PublicKeySpki $PublicKeySpki)),
        ('KeyAlgorithm: ' + $script:IssuerKeyAlgorithm),
        ('PublicKey: ' + [Convert]::ToBase64String($PublicKeySpki)),
        $script:IssuerKeyEnd
    )
    return (($lines -join "`n") + "`n")
}

function ConvertFrom-IssuerPublicKeyText {
    # Strict parser. Any problem is the same generic error: the text comes from outside.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    try {
        if ($Text.Length -eq 0 -or $Text.Length -gt 2048 -or $Text -cmatch '[^\x0A\x0D\x20-\x7E]') { throw 'x' }
        $normalized = $Text.Replace("`r`n", "`n")
        if ($normalized.Contains("`r")) { throw 'x' }
        $lines = [System.Collections.Generic.List[string]]::new($normalized.Split("`n"))
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -eq 0) { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -ne 6 -or $lines[0] -cne $script:IssuerKeyBegin -or $lines[5] -cne $script:IssuerKeyEnd) { throw 'x' }
        $names = @('Contract', 'KeyId', 'KeyAlgorithm', 'PublicKey')
        $values = @{}
        for ($i = 0; $i -lt 4; $i++) {
            $prefix = $names[$i] + ': '
            if (-not $lines[$i + 1].StartsWith($prefix, [System.StringComparison]::Ordinal)) { throw 'x' }
            $values[$names[$i]] = $lines[$i + 1].Substring($prefix.Length)
        }
        if ($values['Contract'] -cnotin $script:SupportedContractVersions) { throw 'x' }
        if ($values['KeyAlgorithm'] -cne $script:IssuerKeyAlgorithm) { throw 'x' }
        [byte[]]$spki = ConvertFrom-StrictBase64 -Text $values['PublicKey']
        if (-not (Test-EcdsaPublicKeySpki $spki)) { throw 'x' }
        if ($values['KeyId'] -cne (Get-PublicKeyFingerprint -PublicKeySpki $spki)) { throw 'x' }
        return [ordered]@{ KeyId = $values['KeyId']; PublicKeySpki = $spki }
    }
    catch { throw 'Invalid issuer key text.' }
}

function Format-KeyFingerprint {
    # 64 lower-case hex -> 16 groups of 4 in upper case, for reading aloud and comparing on two screens.
    param([Parameter(Mandatory)][string]$Fingerprint)
    if ($Fingerprint -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid fingerprint.' }
    $up = $Fingerprint.ToUpperInvariant()
    return ((0..15 | ForEach-Object { $up.Substring($_ * 4, 4) }) -join ' ')
}

Export-ModuleMember -Function @(
    'ConvertTo-CanonicalString', 'ConvertTo-CanonicalJson', 'Get-CanonicalBytes',
    'Get-Sha256Hex', 'Get-PublicKeyFingerprint', 'ConvertFrom-StrictBase64',
    'New-IssuerKeyMaterial', 'New-EcdhKeyMaterial',
    'New-IssuerSignature', 'Test-IssuerSignature',
    'Get-EntryAad', 'Protect-CredentialEntry', 'Unprotect-CredentialEntry',
    'New-MachineIdentityText', 'ConvertFrom-MachineIdentityText',
    'New-CredentialPackage', 'Test-CredentialPackage', 'Get-PackageEntrySecret',
    'New-IssuerPublicKeyText', 'ConvertFrom-IssuerPublicKeyText', 'Format-KeyFingerprint'
)
