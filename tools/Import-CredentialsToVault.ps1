#requires -Version 7.0
<#
.SYNOPSIS
    One-time import of the existing credentials into the vault (step B6.3b). Plan 4.2 of
    docs/migration/catalog-conversion-plan.md. Tool only; never part of the portable application.

.DESCRIPTION
    Reads the LIVE _sisqualMANAGEMENT through a read-only connection that uses only the existing read path
    (app.GetManagedCredentialCatalogue, app.GetManagedCredentialRuntime and the three rule tables), checks everything it
    read, and then:

      DryRun  (the default)  reads and checks, needs no vault, writes nothing. Run it first.
      Import                 adds every credential and every literal rule secret to the vault, ALL OR NOTHING: any
                             failure stops before anything is saved. An existing reference is refused unless -Replace.
                             After the save it compares every salted fingerprint.
      Verify                 reads the source again and compares each value with the salted fingerprint in the vault.
                             Run it after the import and again before the old database is decommissioned.

    Only counts per kind and failure codes with references are printed; a value is never printed. Plaintext values
    live only in memory for the length of the run. The passphrase is a prompt that is never echoed (see
    Read-VaultPassphrase for the test-only environment route). The connection validates the server certificate unless
    -TrustServerCertificate is given, which is an explicit exception.

    [V] On the live server, confirm before the first run that app.GetManagedCredentialRuntime does not write audit rows
    or change state (the plan lists this check), and which login may use the certificate.
#>
[CmdletBinding()]
param(
    [ValidateSet('DryRun', 'Import', 'Verify')][string]$Mode = 'DryRun',
    [Parameter(Mandatory)][string]$SqlInstance,
    [string]$Database = '_sisqualMANAGEMENT',
    [Parameter(Mandatory)][string]$SqlClientPath,
    [switch]$TrustServerCertificate,
    [string]$VaultPath,
    [switch]$Replace
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$plan = $null
$vault = $null
$exitCode = 1
try {
    Import-Module (Join-Path $PSScriptRoot 'lib' 'Sisqual.CredentialVault.psm1')
    Import-Module (Join-Path $PSScriptRoot 'lib' 'Sisqual.CredentialImport.psm1')
    # The vault is opened first (when the mode needs it): if the passphrase or the vault is wrong, no secret is read.
    if ($Mode -ne 'DryRun') {
        if ([string]::IsNullOrWhiteSpace($VaultPath)) { $VaultPath = Get-DefaultVaultPath }
        $passphrase = Read-VaultPassphrase
        $vault = Open-CredentialVault -Path $VaultPath -Passphrase $passphrase
    }
    $source = Read-LiveCredentialSource -SqlInstance $SqlInstance -Database $Database -SqlClientPath $SqlClientPath -TrustServerCertificate:$TrustServerCertificate
    $plan = New-CredentialImportPlan -Catalogue $source.Catalogue -Runtime $source.Runtime -RuleRows $source.RuleRows
    $result = Invoke-CredentialImport -Plan $plan -Mode $Mode -Vault $vault -Replace:$Replace
    Write-Host (Format-ImportReport -Result $result)
    if ($result.Ok -and $Mode -eq 'Import') { Write-Host 'Next: run -Mode Verify, make two encrypted backups of the vault in two places (Invoke-CredentialVault.ps1 -Action Backup), and only then may the old database be decommissioned.' }
    if ($result.Ok -and $Mode -eq 'DryRun') { Write-Host 'Dry run only: nothing was written. Run -Mode Import to import.' }
    if ($result.Ok) { $exitCode = 0 }
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -cnotmatch '^[A-Z][A-Z0-9_]{2,60}$') { $code = 'UNEXPECTED' }
    [Console]::Error.WriteLine('IMPORT_FAILED: ' + $code)
    $exitCode = 1
}
finally {
    if ($null -ne $plan) { Clear-ImportPlan -Plan $plan }
    if ($null -ne $vault) { Close-CredentialVault -Vault $vault }
}
exit $exitCode
