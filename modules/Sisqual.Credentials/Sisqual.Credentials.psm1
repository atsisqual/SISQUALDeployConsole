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

Export-ModuleMember -Function @(
    'ConvertTo-CanonicalString', 'ConvertTo-CanonicalJson', 'Get-CanonicalBytes',
    'Get-Sha256Hex', 'Get-PublicKeyFingerprint', 'ConvertFrom-StrictBase64',
    'New-IssuerKeyMaterial', 'New-EcdhKeyMaterial',
    'New-IssuerSignature', 'Test-IssuerSignature',
    'Get-EntryAad', 'Protect-CredentialEntry', 'Unprotect-CredentialEntry'
)
