#requires -Version 7.0
<#
.SYNOPSIS
    The encrypted vault of the credential tool (step B6.2a). Tool only: it is never part of the portable application.

.DESCRIPTION
    One encrypted file, outside Git, protected by the owner's passphrase through PBKDF2-HMAC-SHA256
    (contracts/credential-package.md, Q9). It holds the issuer key pair (K1: the issuer key travels in the
    vault and in its backups) and, in B6.4, the credentials. No binding to a Windows account.

    File format (ASCII, LF):
      -----BEGIN SISQUAL VAULT-----
      <base64 of the canonical JSON envelope, wrapped at 76 characters>
      -----END SISQUAL VAULT-----
    Envelope: format, version, kdf {name, iterations, salt}, cipher {name, nonce}, ciphertext.
    The ciphertext is AES-256-GCM (ciphertext || 16-byte tag) of the canonical JSON of the vault data; the
    associated data is the canonical JSON of the envelope WITHOUT the ciphertext, so no header field can be
    changed (for example the iteration count) without the open failing.

    Failures are plain codes with no detail: VAULT_FORMAT (the text is not a vault), VAULT_OPEN (wrong
    passphrase or altered file, deliberately indistinguishable), VAULT_WEAK_KDF, VAULT_EXISTS, VAULT_CHANGED,
    VAULT_IN_REPOSITORY, VAULT_PASSPHRASE, VAULT_CLOSED, VAULT_ACL, ISSUER_EXISTS, ISSUER_MISSING.
#>
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')

$script:ArmorBegin = '-----BEGIN SISQUAL VAULT-----'
$script:ArmorEnd = '-----END SISQUAL VAULT-----'
$script:VaultFormat = 'SISQUAL-VAULT'
$script:VaultVersion = 1
$script:KdfName = 'PBKDF2-HMAC-SHA256'
$script:CipherName = 'AES-256-GCM'
$script:MinIterations = 600000
$script:DefaultIterations = 600000
$script:MaxIterations = 100000000
$script:MinPassphraseLength = 14
$script:MinPassphraseDistinct = 6
$script:MaxVaultChars = 8388608

function Stop-Vault {
    param([string]$Code)
    throw $Code
}

# ---------------------------------------------------------------------------
# Passphrase and key derivation
# ---------------------------------------------------------------------------

function Get-PassphraseBytes {
    # UTF-8 bytes of a SecureString. The characters are copied into an array that is cleared at once.
    param([Parameter(Mandatory)][securestring]$Passphrase, [switch]$EnforcePolicy)
    $length = $Passphrase.Length
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase)
    try {
        [char[]]$chars = [char[]]::new($length)
        [System.Runtime.InteropServices.Marshal]::Copy($bstr, $chars, 0, $length)
        try {
            if ($EnforcePolicy) {
                $distinct = @($chars | Sort-Object -Unique).Count
                if ($length -lt $script:MinPassphraseLength -or $distinct -lt $script:MinPassphraseDistinct) { Stop-Vault 'VAULT_PASSPHRASE' }
            }
            [byte[]]$bytes = [System.Text.Encoding]::UTF8.GetBytes($chars)
            return , $bytes
        }
        finally { [Array]::Clear($chars, 0, $chars.Length) }
    }
    finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-VaultKey {
    param([byte[]]$PassphraseBytes, [byte[]]$Salt, [int]$Iterations)
    [byte[]]$key = [System.Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($PassphraseBytes, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256, 32)
    return , $key
}

# ---------------------------------------------------------------------------
# Container: armor, envelope, encryption
# ---------------------------------------------------------------------------

function New-VaultEnvelopeHeader {
    param([int]$Iterations, [byte[]]$Salt, [byte[]]$Nonce)
    return [ordered]@{
        format  = $script:VaultFormat
        version = $script:VaultVersion
        kdf     = [ordered]@{ name = $script:KdfName; iterations = $Iterations; salt = [Convert]::ToBase64String($Salt) }
        cipher  = [ordered]@{ name = $script:CipherName; nonce = [Convert]::ToBase64String($Nonce) }
    }
}

function Get-VaultAad {
    param($Header)
    return (Get-CanonicalBytes -Value ([ordered]@{ format = $Header['format']; version = $Header['version']; kdf = $Header['kdf']; cipher = $Header['cipher'] }))
}

function ConvertTo-VaultText {
    param([byte[]]$Key, [int]$Iterations, [byte[]]$Salt, [byte[]]$Plain)
    [byte[]]$nonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $header = New-VaultEnvelopeHeader -Iterations $Iterations -Salt $Salt -Nonce $nonce
    [byte[]]$aad = Get-VaultAad -Header $header
    [byte[]]$cipher = [byte[]]::new($Plain.Length)
    [byte[]]$tag = [byte[]]::new(16)
    $aes = [System.Security.Cryptography.AesGcm]::new($Key, 16)
    try { $aes.Encrypt($nonce, $Plain, $cipher, $tag, $aad) } finally { $aes.Dispose() }
    [byte[]]$sealed = [byte[]]::new($cipher.Length + 16)
    [Array]::Copy($cipher, 0, $sealed, 0, $cipher.Length)
    [Array]::Copy($tag, 0, $sealed, $cipher.Length, 16)
    $envelope = [ordered]@{ format = $header['format']; version = $header['version']; kdf = $header['kdf']; cipher = $header['cipher']; ciphertext = [Convert]::ToBase64String($sealed) }
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes((ConvertTo-CanonicalJson $envelope)))
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add($script:ArmorBegin)
    for ($i = 0; $i -lt $b64.Length; $i += 76) { $lines.Add($b64.Substring($i, [Math]::Min(76, $b64.Length - $i))) }
    $lines.Add($script:ArmorEnd)
    return (($lines -join "`n") + "`n")
}

function ConvertFrom-VaultText {
    # Format check only (no passphrase): armor, ASCII, size, base64, JSON, members and field formats.
    param([string]$Text)
    try {
        if ([string]::IsNullOrEmpty($Text) -or $Text.Length -gt $script:MaxVaultChars) { Stop-Vault 'VAULT_FORMAT' }
        if ($Text -cmatch '[^\x0A\x0D\x20-\x7E]') { Stop-Vault 'VAULT_FORMAT' }
        $normalized = $Text.Replace("`r`n", "`n")
        if ($normalized.Contains("`r")) { Stop-Vault 'VAULT_FORMAT' }
        $lines = [System.Collections.Generic.List[string]]::new($normalized.Split("`n"))
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Length -eq 0) { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -lt 3 -or $lines[0] -cne $script:ArmorBegin -or $lines[$lines.Count - 1] -cne $script:ArmorEnd) { Stop-Vault 'VAULT_FORMAT' }
        $payload = [System.Text.StringBuilder]::new()
        for ($i = 1; $i -lt ($lines.Count - 1); $i++) {
            if ($lines[$i] -cnotmatch '^[A-Za-z0-9+/]{1,76}={0,2}$') { Stop-Vault 'VAULT_FORMAT' }
            [void]$payload.Append($lines[$i])
        }
        [byte[]]$jsonBytes = ConvertFrom-StrictBase64 -Text $payload.ToString()
        $envelope = [System.Text.Encoding]::ASCII.GetString($jsonBytes) | ConvertFrom-Json -AsHashtable
        $names = @($envelope.Keys | Sort-Object)
        if (($names -join ',') -cne 'cipher,ciphertext,format,kdf,version') { Stop-Vault 'VAULT_FORMAT' }
        if ($envelope['format'] -cne $script:VaultFormat -or $envelope['version'] -isnot [int] -and $envelope['version'] -isnot [long]) { Stop-Vault 'VAULT_FORMAT' }
        if ([long]$envelope['version'] -ne $script:VaultVersion) { Stop-Vault 'VAULT_FORMAT' }
        $kdf = $envelope['kdf']; $cipher = $envelope['cipher']
        if ($kdf -isnot [System.Collections.IDictionary] -or $cipher -isnot [System.Collections.IDictionary]) { Stop-Vault 'VAULT_FORMAT' }
        if ((@($kdf.Keys | Sort-Object) -join ',') -cne 'iterations,name,salt' -or (@($cipher.Keys | Sort-Object) -join ',') -cne 'name,nonce') { Stop-Vault 'VAULT_FORMAT' }
        if ($kdf['name'] -cne $script:KdfName -or $cipher['name'] -cne $script:CipherName) { Stop-Vault 'VAULT_FORMAT' }
        if ($kdf['iterations'] -isnot [int] -and $kdf['iterations'] -isnot [long]) { Stop-Vault 'VAULT_FORMAT' }
        [byte[]]$salt = ConvertFrom-StrictBase64 -Text ([string]$kdf['salt'])
        [byte[]]$nonce = ConvertFrom-StrictBase64 -Text ([string]$cipher['nonce'])
        [byte[]]$sealed = ConvertFrom-StrictBase64 -Text ([string]$envelope['ciphertext'])
        if ($salt.Length -ne 16 -or $nonce.Length -ne 12 -or $sealed.Length -lt 17) { Stop-Vault 'VAULT_FORMAT' }
        $iterations = [long]$kdf['iterations']
        if ($iterations -gt $script:MaxIterations -or $iterations -lt 1) { Stop-Vault 'VAULT_FORMAT' }
        if ($iterations -lt $script:MinIterations) { Stop-Vault 'VAULT_WEAK_KDF' }
        return [pscustomobject]@{ Header = $envelope; Iterations = [int]$iterations; Salt = $salt; Nonce = $nonce; Sealed = $sealed }
    }
    catch {
        $m = [string]$_.Exception.Message
        if ($m -in @('VAULT_FORMAT', 'VAULT_WEAK_KDF')) { throw $m }
        throw 'VAULT_FORMAT'
    }
}

function Open-VaultContent {
    # Decrypts with a derived key; any failure is the same generic VAULT_OPEN.
    param($Parsed, [byte[]]$Key)
    try {
        [byte[]]$aad = Get-VaultAad -Header $Parsed.Header
        $length = $Parsed.Sealed.Length - 16
        [byte[]]$cipher = [byte[]]::new($length)
        [byte[]]$tag = [byte[]]::new(16)
        [Array]::Copy($Parsed.Sealed, 0, $cipher, 0, $length)
        [Array]::Copy($Parsed.Sealed, $length, $tag, 0, 16)
        [byte[]]$plain = [byte[]]::new($length)
        $aes = [System.Security.Cryptography.AesGcm]::new($Key, 16)
        try { $aes.Decrypt($Parsed.Nonce, $cipher, $tag, $plain, $aad) } finally { $aes.Dispose() }
        return , $plain
    }
    catch { throw 'VAULT_OPEN' }
}

# ---------------------------------------------------------------------------
# Files
# ---------------------------------------------------------------------------

function Test-InsideRepository {
    param([string]$Directory)
    $dir = $Directory
    while (-not [string]::IsNullOrEmpty($dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $true }
        $parent = [System.IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $false
}

function Protect-VaultFileAcl {
    # Windows: no inherited rules; only the current user, Administrators and SYSTEM. Elsewhere the mode is 0600.
    param([string]$Path)
    try {
        if ($IsWindows) {
            $acl = Get-Acl -LiteralPath $Path
            $acl.SetAccessRuleProtection($true, $false)
            foreach ($rule in @($acl.Access)) { [void]$acl.RemoveAccessRule($rule) }
            $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
            $admins = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
            $system = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
            foreach ($sid in @($me, $admins, $system)) {
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))
            }
            Set-Acl -LiteralPath $Path -AclObject $acl
        }
        else { [System.IO.File]::SetUnixFileMode($Path, ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)) }
    }
    catch { Stop-Vault 'VAULT_ACL' }
}

function Write-VaultFile {
    param([string]$Path, [string]$Text, [switch]$Create)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    $tmp = Join-Path $dir ('.' + [System.IO.Path]::GetFileName($Path) + '.tmp-' + [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $Text, [System.Text.UTF8Encoding]::new($false))
        Protect-VaultFileAcl -Path $tmp
        if ($Create) { [System.IO.File]::Move($tmp, $Path) }
        else { [System.IO.File]::Replace($tmp, $Path, ($Path + '.prev')) }
    }
    catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        if ($_.Exception.Message -ceq 'VAULT_ACL') { throw 'VAULT_ACL' }
        throw
    }
}

function Get-FileSha256Hex {
    param([string]$Path)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path))).ToLowerInvariant()
}

function Read-VaultFileText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Vault 'VAULT_FORMAT' }
    if ((Get-Item -LiteralPath $Path).Length -gt $script:MaxVaultChars) { Stop-Vault 'VAULT_FORMAT' }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII)
}

function ConvertTo-VaultPlain {
    param($Data)
    [byte[]]$bytes = Get-CanonicalBytes -Value $Data
    return , $bytes
}

function Get-UtcNowText { return [datetime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture) }

# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

function New-CredentialVault {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][securestring]$Passphrase, [int]$Iterations = $script:DefaultIterations)
    $full = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { Stop-Vault 'VAULT_EXISTS' }
    $dir = [System.IO.Path]::GetDirectoryName($full)
    if (Test-InsideRepository -Directory $dir) { Stop-Vault 'VAULT_IN_REPOSITORY' }
    if ($Iterations -lt $script:MinIterations -or $Iterations -gt $script:MaxIterations) { Stop-Vault 'VAULT_WEAK_KDF' }
    [byte[]]$pw = Get-PassphraseBytes -Passphrase $Passphrase -EnforcePolicy
    try {
        [void][System.IO.Directory]::CreateDirectory($dir)
        [byte[]]$salt = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
        [byte[]]$key = Get-VaultKey -PassphraseBytes $pw -Salt $salt -Iterations $Iterations
        $now = Get-UtcNowText
        $data = [ordered]@{ formatVersion = 1; vaultId = [guid]::NewGuid().ToString(); revision = 1; createdAt = $now; updatedAt = $now; issuer = $null; secrets = @() }
        Write-VaultFile -Path $full -Text (ConvertTo-VaultText -Key $key -Iterations $Iterations -Salt $salt -Plain (ConvertTo-VaultPlain $data)) -Create
        return [pscustomobject]@{ Path = $full; Data = $data; Revision = 1L; FileSha256 = (Get-FileSha256Hex $full); Key = $key; Salt = $salt; Iterations = $Iterations; Closed = $false }
    }
    finally { [Array]::Clear($pw, 0, $pw.Length) }
}

function Open-CredentialVault {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][securestring]$Passphrase)
    $full = [System.IO.Path]::GetFullPath($Path)
    $parsed = ConvertFrom-VaultText -Text (Read-VaultFileText -Path $full)
    [byte[]]$pw = Get-PassphraseBytes -Passphrase $Passphrase
    try {
        [byte[]]$key = Get-VaultKey -PassphraseBytes $pw -Salt $parsed.Salt -Iterations $parsed.Iterations
        [byte[]]$plain = Open-VaultContent -Parsed $parsed -Key $key
        try {
            # -DateKind String: the timestamps are text, and must stay text (the canonical form refuses DateTime).
            $data = [System.Text.Encoding]::ASCII.GetString($plain) | ConvertFrom-Json -AsHashtable -DateKind String
            if ($data -isnot [System.Collections.IDictionary] -or [long]$data['formatVersion'] -ne 1) { Stop-Vault 'VAULT_FORMAT' }
        }
        finally { [Array]::Clear($plain, 0, $plain.Length) }
        return [pscustomobject]@{ Path = $full; Data = $data; Revision = [long]$data['revision']; FileSha256 = (Get-FileSha256Hex $full); Key = $key; Salt = $parsed.Salt; Iterations = $parsed.Iterations; Closed = $false }
    }
    finally { [Array]::Clear($pw, 0, $pw.Length) }
}

function Save-CredentialVault {
    param([Parameter(Mandatory)]$Vault)
    if ($Vault.Closed) { Stop-Vault 'VAULT_CLOSED' }
    if (-not (Test-Path -LiteralPath $Vault.Path -PathType Leaf) -or (Get-FileSha256Hex $Vault.Path) -cne $Vault.FileSha256) { Stop-Vault 'VAULT_CHANGED' }
    $Vault.Data['revision'] = [long]$Vault.Data['revision'] + 1
    $Vault.Data['updatedAt'] = Get-UtcNowText
    Write-VaultFile -Path $Vault.Path -Text (ConvertTo-VaultText -Key $Vault.Key -Iterations $Vault.Iterations -Salt $Vault.Salt -Plain (ConvertTo-VaultPlain $Vault.Data))
    $Vault.Revision = [long]$Vault.Data['revision']
    $Vault.FileSha256 = Get-FileSha256Hex $Vault.Path
}

function Close-CredentialVault {
    param([Parameter(Mandatory)]$Vault)
    if ($null -ne $Vault.Key) { [Array]::Clear($Vault.Key, 0, $Vault.Key.Length) }
    $Vault.Closed = $true
}

function New-VaultIssuerKey {
    # Creates the issuer key pair inside the open vault (in memory; call Save-CredentialVault to persist it).
    param([Parameter(Mandatory)]$Vault, [switch]$Replace)
    if ($Vault.Closed) { Stop-Vault 'VAULT_CLOSED' }
    if ($null -ne $Vault.Data['issuer'] -and -not $Replace) { Stop-Vault 'ISSUER_EXISTS' }
    $key = New-IssuerKeyMaterial
    $Vault.Data['issuer'] = [ordered]@{ keyId = $key.KeyId; publicKeySpki = [Convert]::ToBase64String($key.PublicKeySpki); privateKeyPkcs8 = [Convert]::ToBase64String($key.PrivateKeyPkcs8); createdAt = (Get-UtcNowText) }
    [Array]::Clear($key.PrivateKeyPkcs8, 0, $key.PrivateKeyPkcs8.Length)
    return (Get-VaultIssuerInfo -Vault $Vault)
}

function Get-VaultIssuerInfo {
    # The public part only. The private key is never returned.
    param([Parameter(Mandatory)]$Vault)
    if ($Vault.Closed) { Stop-Vault 'VAULT_CLOSED' }
    $issuer = $Vault.Data['issuer']
    if ($null -eq $issuer) { return $null }
    [byte[]]$spki = [Convert]::FromBase64String([string]$issuer['publicKeySpki'])
    return [pscustomobject]@{ KeyId = [string]$issuer['keyId']; PublicKeySpki = $spki; PublicKeyBase64 = [string]$issuer['publicKeySpki']; CreatedAt = [string]$issuer['createdAt'] }
}

function Invoke-VaultIssuerSign {
    # Signs bytes with the issuer private key held in the vault and returns { issuerKeyId, algorithm, value }.
    param([Parameter(Mandatory)]$Vault, [Parameter(Mandatory)][byte[]]$Data)
    if ($Vault.Closed) { Stop-Vault 'VAULT_CLOSED' }
    $issuer = $Vault.Data['issuer']
    if ($null -eq $issuer) { Stop-Vault 'ISSUER_MISSING' }
    [byte[]]$private = [Convert]::FromBase64String([string]$issuer['privateKeyPkcs8'])
    try { return (New-IssuerSignature -PrivateKeyPkcs8 $private -Data $Data) }
    finally { [Array]::Clear($private, 0, $private.Length) }
}

function Backup-CredentialVault {
    # Copies the encrypted file to a new, never overwritten, file in the destination folder and verifies it.
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$DestinationFolder, [ValidatePattern('^\d{8}T\d{6}Z$')][string]$Stamp)
    $full = [System.IO.Path]::GetFullPath($Path)
    [void](ConvertFrom-VaultText -Text (Read-VaultFileText -Path $full))
    $destDir = [System.IO.Path]::GetFullPath($DestinationFolder)
    if (Test-InsideRepository -Directory $destDir) { Stop-Vault 'VAULT_IN_REPOSITORY' }
    [void][System.IO.Directory]::CreateDirectory($destDir)
    $when = [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
    if (-not [string]::IsNullOrEmpty($Stamp)) { $when = $Stamp }
    $target = Join-Path $destDir ([System.IO.Path]::GetFileName($full) + '.' + $when + '.bak')
    if (Test-Path -LiteralPath $target) { Stop-Vault 'VAULT_EXISTS' }
    Write-VaultFile -Path $target -Text (Read-VaultFileText -Path $full) -Create
    $source = Get-FileSha256Hex $full
    if ((Get-FileSha256Hex $target) -cne $source) { Remove-Item -LiteralPath $target -Force; Stop-Vault 'VAULT_CHANGED' }
    return [pscustomobject]@{ BackupPath = $target; Sha256 = $source }
}

function Restore-CredentialVault {
    # The restore test: the backup must open with the passphrase before anything is replaced.
    param([Parameter(Mandatory)][string]$BackupPath, [Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][securestring]$Passphrase, [switch]$Force)
    $full = [System.IO.Path]::GetFullPath($Path)
    $probe = Open-CredentialVault -Path $BackupPath -Passphrase $Passphrase
    $info = [pscustomobject]@{ Revision = $probe.Revision; VaultId = [string]$probe.Data['vaultId']; Replaced = $null }
    Close-CredentialVault -Vault $probe
    if (Test-InsideRepository -Directory ([System.IO.Path]::GetDirectoryName($full))) { Stop-Vault 'VAULT_IN_REPOSITORY' }
    [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
    if (Test-Path -LiteralPath $full) {
        if (-not $Force) { Stop-Vault 'VAULT_EXISTS' }
        $info.Replaced = $full + '.replaced-' + [datetime]::UtcNow.ToString("yyyyMMdd'T'HHmmss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        [System.IO.File]::Move($full, $info.Replaced)
    }
    Write-VaultFile -Path $full -Text (Read-VaultFileText -Path $BackupPath) -Create
    return $info
}

Export-ModuleMember -Function @(
    'New-CredentialVault', 'Open-CredentialVault', 'Save-CredentialVault', 'Close-CredentialVault',
    'New-VaultIssuerKey', 'Get-VaultIssuerInfo', 'Invoke-VaultIssuerSign',
    'Backup-CredentialVault', 'Restore-CredentialVault'
)
