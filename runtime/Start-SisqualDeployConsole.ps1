[CmdletBinding()]
param(
    [string]$LogRoot = '',
    [ValidateRange(1, 3650)][int]$RetentionDays = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runtimeRoot = $PSScriptRoot
$packageRoot = Split-Path -Parent $runtimeRoot
$bootstrapLibrary = Join-Path $runtimeRoot 'RuntimeBootstrap.ps1'

if (-not (Test-Path -LiteralPath $bootstrapLibrary -PathType Leaf)) {
    Write-Error 'SISQUALDeployConsole runtime bootstrap library is missing.'
    exit 13
}

. $bootstrapLibrary
$defaults = Get-SisqualRuntimeDefaults
$hostResult = Test-SisqualRuntimeHost -ExpectedVersion $defaults.ExpectedPowerShellVersion
if (-not $hostResult.Success) {
    Write-Error ('SISQUALDeployConsole requires portable PowerShell {0} Core x64; actual version={1}, edition={2}, x64={3}.' -f $hostResult.ExpectedVersion, $hostResult.ActualVersion, $hostResult.PSEdition, $hostResult.Is64BitProcess)
    exit 10
}

if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = $defaults.DefaultLogRoot
}

try {
    $logContext = Initialize-SisqualRuntimeLog -LogRoot $LogRoot -RetentionDays $RetentionDays
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'BOOTSTRAP_STARTED'
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'HOST_VALID'
}
catch {
    Write-Error ('SISQUALDeployConsole could not initialize its text log: {0}' -f $_.Exception.Message)
    exit 11
}

$manifestPath = Join-Path $packageRoot $defaults.ManifestFileName
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'MANIFEST_MISSING' -Level 'ERROR'
    Write-Error 'SISQUALDeployConsole package manifest is missing. Startup is blocked.'
    exit 20
}

# Phase 3A deliberately stops here. The B6.2 signer/verifier work owns the
# signature/trust implementation. Until that verifier is integrated, no module,
# catalog, credential package, HTTP adapter or engine may be loaded.
Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'INTEGRITY_VERIFIER_UNAVAILABLE' -Level 'ERROR'
Write-Error 'SISQUALDeployConsole package integrity verifier is not integrated yet. Startup is blocked.'
exit 21
