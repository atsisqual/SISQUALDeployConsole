#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('SourceCreate', 'SourceReopen', 'Destination', 'Delete')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9_.-]{1,120}$')]
    [string]$KeyName,

    [Parameter(Mandatory)]
    [string]$CredentialModulePath,

    [string]$IdentityPath,
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$provider = [System.Security.Cryptography.CngProvider]::MicrosoftSoftwareKeyStorageProvider
$algorithm = [System.Security.Cryptography.CngAlgorithm]::ECDiffieHellmanP256
$machineOpen = [System.Security.Cryptography.CngKeyOpenOptions]::MachineKey

function Get-Sha256Hex {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function New-CheckList {
    return [System.Collections.Generic.List[object]]::new()
}

function Add-Check {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$List,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Detail
    )
    $List.Add([pscustomobject]@{
        id = $Id
        status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        detail = $Detail
    })
    if (-not $Passed) { throw "$Id failed: $Detail" }
}

function Test-KeyExists {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $key = [System.Security.Cryptography.CngKey]::Open($Name, $provider, $machineOpen)
        try { return $true } finally { $key.Dispose() }
    }
    catch [System.Security.Cryptography.CryptographicException] { return $false }
}

function New-MachineKey {
    param([Parameter(Mandatory)][string]$Name)
    $p = [System.Security.Cryptography.CngKeyCreationParameters]::new()
    $p.Provider = $provider
    $p.KeyUsage = [System.Security.Cryptography.CngKeyUsages]::KeyAgreement
    $p.ExportPolicy = [System.Security.Cryptography.CngExportPolicies]::None
    $p.KeyCreationOptions = [System.Security.Cryptography.CngKeyCreationOptions]::MachineKey
    return [System.Security.Cryptography.CngKey]::Create($algorithm, $Name, $p)
}

function Open-MachineKey {
    param([Parameter(Mandatory)][string]$Name)
    return [System.Security.Cryptography.CngKey]::Open($Name, $provider, $machineOpen)
}

function Assert-PrivateExportBlocked {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellmanCng]$Ecdh,
        [Parameter(Mandatory)][System.Security.Cryptography.CngKey]$CngKey,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Checks
    )

    $pkcs8Blocked = $false
    $privateBytes = $null
    try {
        $privateBytes = $Ecdh.ExportPkcs8PrivateKey()
    }
    catch [System.Security.Cryptography.CryptographicException] {
        $pkcs8Blocked = $true
    }
    finally {
        if ($null -ne $privateBytes) { [Array]::Clear($privateBytes, 0, $privateBytes.Length) }
    }
    Add-Check $Checks 'PRIVATE_EXPORT_PKCS8_BLOCKED' $pkcs8Blocked 'PKCS#8 private-key export must be rejected.'

    $blobBlocked = $false
    $blob = $null
    try {
        $blob = $CngKey.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPrivateBlob)
    }
    catch [System.Security.Cryptography.CryptographicException] {
        $blobBlocked = $true
    }
    finally {
        if ($null -ne $blob) { [Array]::Clear($blob, 0, $blob.Length) }
    }
    Add-Check $Checks 'PRIVATE_EXPORT_CNG_BLOCKED' $blobBlocked 'CNG ECC private-blob export must be rejected.'
}

function Get-KeyIdentity {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellmanCng]$Ecdh,
        [Parameter(Mandatory)][System.Security.Cryptography.CngKey]$CngKey
    )
    [byte[]]$spki = $Ecdh.ExportSubjectPublicKeyInfo()
    return [ordered]@{
        keyName = $CngKey.KeyName
        provider = $CngKey.Provider.Provider
        algorithm = $CngKey.Algorithm.Algorithm
        keySize = $Ecdh.KeySize
        machineKey = $CngKey.IsMachineKey
        exportPolicy = $CngKey.ExportPolicy.ToString()
        keyFingerprint = Get-Sha256Hex $spki
        publicKeySpki = [Convert]::ToBase64String($spki)
    }
}

function Test-CredentialInterop {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellmanCng]$Ecdh,
        [Parameter(Mandatory)]$Identity,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Checks
    )

    Import-Module $CredentialModulePath -Force
    [byte[]]$secret = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $plain = $null
    try {
        [byte[]]$public = [Convert]::FromBase64String([string]$Identity.publicKeySpki)
        [byte[]]$aad = Get-EntryAad -PackageId '3f2b8c1e-0a4d-4e6b-9c11-5d7e2a9b4f01' -ServerCode 'SPIKE_SERVER' -KeyFingerprint ([string]$Identity.keyFingerprint) -CredentialRef 'SPIKE.IDENTITY' -Sequence 1
        $entry = Protect-CredentialEntry -MachinePublicKeySpki $public -Secret $secret -Aad $aad
        $plain = Unprotect-CredentialEntry -MachineKey $Ecdh -Entry $entry -Aad $aad
        $same = ([Convert]::ToBase64String($secret) -ceq [Convert]::ToBase64String($plain))
        Add-Check $Checks 'CREDENTIAL_MODULE_INTEROP' $same 'Existing Sisqual.Credentials entry encryption/decryption must work with the non-exportable CNG key.'
    }
    finally {
        if ($null -ne $plain) { [Array]::Clear($plain, 0, $plain.Length) }
        [Array]::Clear($secret, 0, $secret.Length)
    }
}

function Test-WrongMachineCannotDecrypt {
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.ECDiffieHellmanCng]$DestinationEcdh,
        [Parameter(Mandatory)]$SourceIdentity,
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Checks
    )

    Import-Module $CredentialModulePath -Force
    [byte[]]$secret = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $wrongMachineRejected = $false
    try {
        [byte[]]$sourcePublic = [Convert]::FromBase64String([string]$SourceIdentity.publicKeySpki)
        [byte[]]$aad = Get-EntryAad -PackageId '6c788b25-9b88-40d5-a603-a1f3f1860648' -ServerCode 'SPIKE_SERVER' -KeyFingerprint ([string]$SourceIdentity.keyFingerprint) -CredentialRef 'SPIKE.WRONG_MACHINE' -Sequence 1
        $entry = Protect-CredentialEntry -MachinePublicKeySpki $sourcePublic -Secret $secret -Aad $aad
        try {
            [byte[]]$unexpected = Unprotect-CredentialEntry -MachineKey $DestinationEcdh -Entry $entry -Aad $aad
            [Array]::Clear($unexpected, 0, $unexpected.Length)
        }
        catch {
            $wrongMachineRejected = ($_.Exception.Message -eq 'DECRYPT')
        }
        Add-Check $Checks 'SOURCE_ENTRY_REJECTED_ON_DESTINATION' $wrongMachineRejected 'An entry encrypted for machine A must not decrypt with machine B private key.'
    }
    finally {
        [Array]::Clear($secret, 0, $secret.Length)
    }
}

function Write-Report {
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Checks,
        [Parameter(Mandatory)][string]$Mode,
        $Identity
    )
    if ([string]::IsNullOrWhiteSpace($ReportPath)) { return }
    $parent = Split-Path -Parent $ReportPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    $report = [ordered]@{
        schema = 'SISQUAL_PHASE1B_MACHINE_IDENTITY_SPIKE_V1'
        action = $Mode
        utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        machineName = [Environment]::MachineName
        powerShell = $PSVersionTable.PSVersion.ToString()
        overall = $(if (@($Checks | Where-Object status -eq 'FAIL').Count -eq 0) { 'PASS' } else { 'FAIL' })
        fingerprint = $(if ($null -ne $Identity) { [string]$Identity.keyFingerprint } else { $null })
        checks = @($Checks)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding ascii
}

if (-not (Test-Path -LiteralPath $CredentialModulePath -PathType Leaf)) {
    throw "Credential module not found: $CredentialModulePath"
}

$checks = New-CheckList
$identity = $null
$key = $null
$ecdh = $null

try {
    switch ($Action) {
        'SourceCreate' {
            Add-Check $checks 'KEY_ABSENT_BEFORE_CREATE' (-not (Test-KeyExists $KeyName)) 'The test key name must be absent before source creation.'
            $key = New-MachineKey $KeyName
            $ecdh = [System.Security.Cryptography.ECDiffieHellmanCng]::new($key)
            $identity = Get-KeyIdentity $ecdh $key
            Add-Check $checks 'MACHINE_SCOPE' ([bool]$identity.machineKey) 'The CNG key must be in the machine key store.'
            Add-Check $checks 'SOFTWARE_KSP' ([string]$identity.provider -ceq $provider.Provider) 'The spike uses Microsoft Software Key Storage Provider.'
            Add-Check $checks 'ECDH_P256' (([string]$identity.algorithm -match 'ECDH') -and [int]$identity.keySize -eq 256) 'The machine key must be ECDH P-256.'
            Add-Check $checks 'EXPORT_POLICY_NONE' ([string]$identity.exportPolicy -eq 'None') 'The CNG export policy must be None.'
            Add-Check $checks 'PUBLIC_EXPORT' (-not [string]::IsNullOrWhiteSpace([string]$identity.publicKeySpki)) 'Public SPKI export must succeed.'
            Assert-PrivateExportBlocked $ecdh $key $checks
            Test-CredentialInterop $ecdh $identity $checks
            if ([string]::IsNullOrWhiteSpace($IdentityPath)) { throw 'IdentityPath is required for SourceCreate.' }
            $identity | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $IdentityPath -Encoding ascii
        }
        'SourceReopen' {
            if ([string]::IsNullOrWhiteSpace($IdentityPath) -or -not (Test-Path -LiteralPath $IdentityPath)) { throw 'Existing IdentityPath is required for SourceReopen.' }
            $expected = Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json
            Add-Check $checks 'KEY_PRESENT_AFTER_FOLDER_REPLACEMENT' (Test-KeyExists $KeyName) 'The machine key must remain after the portable folder is replaced.'
            $key = Open-MachineKey $KeyName
            $ecdh = [System.Security.Cryptography.ECDiffieHellmanCng]::new($key)
            $identity = Get-KeyIdentity $ecdh $key
            Add-Check $checks 'FINGERPRINT_STABLE' ([string]$identity.keyFingerprint -ceq [string]$expected.keyFingerprint) 'Reopening by name must return the same machine identity.'
            Assert-PrivateExportBlocked $ecdh $key $checks
            Test-CredentialInterop $ecdh $identity $checks
        }
        'Destination' {
            if ([string]::IsNullOrWhiteSpace($IdentityPath) -or -not (Test-Path -LiteralPath $IdentityPath)) { throw 'Source IdentityPath is required for Destination.' }
            $source = Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json
            Add-Check $checks 'COPIED_FOLDER_HAS_NO_PRIVATE_KEY' (-not (Test-KeyExists $KeyName)) 'The same logical key name must not exist on the second VM before local creation.'
            $key = New-MachineKey $KeyName
            $ecdh = [System.Security.Cryptography.ECDiffieHellmanCng]::new($key)
            $identity = Get-KeyIdentity $ecdh $key
            Add-Check $checks 'DESTINATION_IDENTITY_DIFFERENT' ([string]$identity.keyFingerprint -cne [string]$source.keyFingerprint) 'Creating the same logical identity on a second VM must create a different key.'
            Assert-PrivateExportBlocked $ecdh $key $checks
            Test-CredentialInterop $ecdh $identity $checks
            Test-WrongMachineCannotDecrypt $ecdh $source $checks
        }
        'Delete' {
            if (Test-KeyExists $KeyName) {
                $key = Open-MachineKey $KeyName
                $key.Delete()
                $key.Dispose()
                $key = $null
            }
            Add-Check $checks 'KEY_REMOVED' (-not (Test-KeyExists $KeyName)) 'The test key must be deleted during cleanup.'
        }
    }

    Write-Report $checks $Action $identity
    Write-Host ("Machine identity spike {0}: PASS" -f $Action)
}
catch {
    try { Write-Report $checks $Action $identity } catch { }
    throw
}
finally {
    if ($null -ne $ecdh) { $ecdh.Dispose() }
    if ($null -ne $key) { $key.Dispose() }
}
