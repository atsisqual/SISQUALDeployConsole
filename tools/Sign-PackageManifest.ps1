#requires -Version 7.0
<#
.SYNOPSIS
    The real signer for tools/Seal-Package.ps1 (step B6.2b). Run it with -SignerScript.

.DESCRIPTION
    Seal-Package calls it as:  pwsh -NoProfile -File Sign-PackageManifest.ps1 -InputFile <bytes> -OutputFile <json>
    and passes nothing else, so the vault comes from -VaultPath, SISQUAL_VAULT_PATH, or the ADR-0007 folder.

    It opens the credential vault with the owner's passphrase (an interactive prompt that is never echoed; the
    environment route is for tests and unattended runs only, see Read-VaultPassphrase), signs the input bytes with
    the issuer key inside the vault, writes { issuerKeyId, algorithm, value } and closes the vault, which zeroes
    the derived key. The vault is only read, never saved. The private key never leaves the process, and nothing
    secret is written to any stream: a failure is a plain code such as VAULT_OPEN on the error stream, exit 1,
    and no output file is left behind.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$OutputFile,
    [string]$VaultPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$vault = $null
$exitCode = 0
try {
    Import-Module (Join-Path $PSScriptRoot 'lib' 'Sisqual.CredentialVault.psm1')
    if ([string]::IsNullOrWhiteSpace($VaultPath)) { $VaultPath = Get-DefaultVaultPath }
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) { throw 'SIGNER_INPUT' }
    if ((Get-Item -LiteralPath $InputFile).Length -gt 1048576) { throw 'SIGNER_INPUT' }
    [byte[]]$data = [System.IO.File]::ReadAllBytes($InputFile)
    $passphrase = Read-VaultPassphrase
    $vault = Open-CredentialVault -Path $VaultPath -Passphrase $passphrase
    $signature = Invoke-VaultIssuerSign -Vault $vault -Data $data
    $json = ([ordered]@{ issuerKeyId = $signature['issuerKeyId']; algorithm = $signature['algorithm']; value = $signature['value'] } | ConvertTo-Json -Compress)
    [System.IO.File]::WriteAllText($OutputFile, $json, [System.Text.UTF8Encoding]::new($false))
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -cnotmatch '^[A-Z][A-Z0-9_]{2,40}$') { $code = 'UNEXPECTED' }
    [Console]::Error.WriteLine('SIGNER_FAILED: ' + $code)
    Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
    $exitCode = 1
}
finally {
    if ($null -ne $vault) { Close-CredentialVault -Vault $vault }
}
exit $exitCode
