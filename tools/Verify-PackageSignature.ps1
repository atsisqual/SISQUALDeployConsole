#requires -Version 7.0
<#
.SYNOPSIS
    The real verifier for tools/Seal-Package.ps1 (step B6.2b). Run it with -VerifierScript.

.DESCRIPTION
    Seal-Package calls it as:  pwsh -NoProfile -File Verify-PackageSignature.ps1 -InputFile <bytes> -SignatureFile <json>
    and only looks at the exit code: 0 when the signature is valid, 1 for anything else. Fail closed: a missing or
    invalid issuer key file, an unreadable signature and a wrong algorithm all end in exit 1.

    The trusted key is the pinned issuer public key text (the file written by Invoke-CredentialVault.ps1
    -Action ExportIssuerKey), taken from -IssuerKeyFile, SISQUAL_ISSUER_KEY_FILE, or the ADR-0007 folder on
    Windows. It needs no passphrase and no vault, and it never trusts the key id written in the signature.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputFile,
    [Parameter(Mandatory)][string]$SignatureFile,
    [string]$IssuerKeyFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$exitCode = 1
try {
    Import-Module (Join-Path $PSScriptRoot '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')
    if ([string]::IsNullOrWhiteSpace($IssuerKeyFile)) { $IssuerKeyFile = [Environment]::GetEnvironmentVariable('SISQUAL_ISSUER_KEY_FILE') }
    if ([string]::IsNullOrWhiteSpace($IssuerKeyFile) -and $IsWindows) { $IssuerKeyFile = 'C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\issuer-public-key.txt' }
    if ([string]::IsNullOrWhiteSpace($IssuerKeyFile) -or -not (Test-Path -LiteralPath $IssuerKeyFile -PathType Leaf) -or (Get-Item -LiteralPath $IssuerKeyFile).Length -gt 4096) { throw 'ISSUER_KEY_FILE' }
    $issuer = ConvertFrom-IssuerPublicKeyText -Text ([System.IO.File]::ReadAllText($IssuerKeyFile, [System.Text.Encoding]::ASCII))
    if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf) -or (Get-Item -LiteralPath $InputFile).Length -gt 1048576) { throw 'VERIFIER_INPUT' }
    if (-not (Test-Path -LiteralPath $SignatureFile -PathType Leaf) -or (Get-Item -LiteralPath $SignatureFile).Length -gt 4096) { throw 'SIGNATURE_FILE' }
    $signature = [System.IO.File]::ReadAllText($SignatureFile, [System.Text.Encoding]::ASCII) | ConvertFrom-Json -DateKind String
    [byte[]]$data = [System.IO.File]::ReadAllBytes($InputFile)
    if (Test-IssuerSignature -PublicKeySpki $issuer.PublicKeySpki -Data $data -Signature $signature) { $exitCode = 0 }
    else { [Console]::Error.WriteLine('VERIFIER_FAILED: SIGNATURE_INVALID') }
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -cnotmatch '^[A-Z][A-Z0-9_]{2,40}$') { $code = 'UNEXPECTED' }
    [Console]::Error.WriteLine('VERIFIER_FAILED: ' + $code)
    $exitCode = 1
}
exit $exitCode
