#requires -Version 7.0
<#
.SYNOPSIS
    The command of the credential vault (step B6.2b): Init, Info, ExportIssuerKey, Backup, Restore.

.DESCRIPTION
    Tool only; never part of the portable application. The vault path comes from -VaultPath, SISQUAL_VAULT_PATH
    or the ADR-0007 folder. The passphrase is an interactive prompt that is never echoed (see Read-VaultPassphrase
    for the test-only environment route). Nothing secret is printed: the output is paths, revisions, the public key
    fingerprint and plain failure codes on the error stream (exit 1).

      Init             creates the vault (passphrase asked twice) and the issuer key pair inside it.
      Info             opens the vault and shows its id, revision and the issuer key fingerprint.
      ExportIssuerKey  writes the issuer PUBLIC key text to -OutputFile (never overwritten). That text is what the
                       operator pins on each machine, after comparing the fingerprint shown here with the one the
                       application shows.
      Backup           copies the encrypted file to -DestinationFolder (never overwritten) and verifies the copy.
      Restore          opens -BackupPath with the passphrase (the restore test) and puts it at the vault path;
                       -Force keeps the replaced file as .replaced-<time>.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Init', 'Info', 'ExportIssuerKey', 'Backup', 'Restore')][string]$Action,
    [string]$VaultPath,
    [string]$OutputFile,
    [string]$DestinationFolder,
    [string]$BackupPath,
    [switch]$Force
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vault = $null
$exitCode = 0
try {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')
    Import-Module (Join-Path $PSScriptRoot 'lib' 'Sisqual.CredentialVault.psm1')
    if ([string]::IsNullOrWhiteSpace($VaultPath)) { $VaultPath = Get-DefaultVaultPath }
    switch ($Action) {
        'Init' {
            $passphrase = Read-VaultPassphrase -Prompt 'Choose the vault passphrase (at least 14 characters)' -Twice
            $vault = New-CredentialVault -Path $VaultPath -Passphrase $passphrase
            $info = New-VaultIssuerKey -Vault $vault
            Save-CredentialVault -Vault $vault
            Write-Host ('Vault created: {0}' -f $vault.Path)
            Write-Host ('Issuer key id: {0}' -f (Format-KeyFingerprint -Fingerprint $info.KeyId))
            Write-Host 'Next: write the passphrase down for the second custodian, make two backups in two places (Backup), and export the issuer public key (ExportIssuerKey).'
        }
        'Info' {
            $passphrase = Read-VaultPassphrase
            $vault = Open-CredentialVault -Path $VaultPath -Passphrase $passphrase
            $info = Get-VaultIssuerInfo -Vault $vault
            Write-Host ('Vault: {0}' -f $vault.Path)
            Write-Host ('Vault id: {0}' -f [string]$vault.Data['vaultId'])
            Write-Host ('Revision: {0}' -f $vault.Revision)
            if ($null -eq $info) { Write-Host 'Issuer key: none' }
            else {
                Write-Host ('Issuer key id: {0}' -f (Format-KeyFingerprint -Fingerprint $info.KeyId))
                Write-Host ('Issuer key created: {0}' -f $info.CreatedAt)
            }
        }
        'ExportIssuerKey' {
            if ([string]::IsNullOrWhiteSpace($OutputFile)) { throw 'OUTPUT_REQUIRED' }
            $target = [System.IO.Path]::GetFullPath($OutputFile)
            if (Test-Path -LiteralPath $target) { throw 'OUTPUT_EXISTS' }
            $passphrase = Read-VaultPassphrase
            $vault = Open-CredentialVault -Path $VaultPath -Passphrase $passphrase
            $info = Get-VaultIssuerInfo -Vault $vault
            if ($null -eq $info) { throw 'ISSUER_MISSING' }
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
            [System.IO.File]::WriteAllText($target, (New-IssuerPublicKeyText -PublicKeySpki $info.PublicKeySpki), [System.Text.UTF8Encoding]::new($false))
            Write-Host ('Issuer public key written: {0}' -f $target)
            Write-Host ('Issuer key id: {0}' -f (Format-KeyFingerprint -Fingerprint $info.KeyId))
            Write-Host 'Compare this fingerprint with the one the application shows before pinning the key.'
        }
        'Backup' {
            if ([string]::IsNullOrWhiteSpace($DestinationFolder)) { throw 'DESTINATION_REQUIRED' }
            $result = Backup-CredentialVault -Path $VaultPath -DestinationFolder $DestinationFolder
            Write-Host ('Backup written: {0}' -f $result.BackupPath)
            Write-Host ('SHA-256: {0}' -f $result.Sha256)
        }
        'Restore' {
            if ([string]::IsNullOrWhiteSpace($BackupPath)) { throw 'BACKUP_REQUIRED' }
            $passphrase = Read-VaultPassphrase
            $result = Restore-CredentialVault -BackupPath $BackupPath -Path $VaultPath -Passphrase $passphrase -Force:$Force
            Write-Host ('Restored revision {0} of vault {1} to {2}' -f $result.Revision, $result.VaultId, ([System.IO.Path]::GetFullPath($VaultPath)))
            if ($null -ne $result.Replaced) { Write-Host ('The replaced file was kept as: {0}' -f $result.Replaced) }
        }
    }
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -cnotmatch '^[A-Z][A-Z0-9_]{2,40}$') { $code = 'UNEXPECTED' }
    [Console]::Error.WriteLine('VAULT_COMMAND_FAILED: ' + $code)
    $exitCode = 1
}
finally {
    if ($null -ne $vault) { Close-CredentialVault -Vault $vault }
}
exit $exitCode
