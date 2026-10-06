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
    [Console]::Error.WriteLine('SISQUALDeployConsole runtime bootstrap library is missing.')
    exit 13
}

. $bootstrapLibrary
$defaults = Get-SisqualRuntimeDefaults
$hostResult = Test-SisqualRuntimeHost -ExpectedVersion $defaults.ExpectedPowerShellVersion
if (-not $hostResult.Success) {
    [Console]::Error.WriteLine(('SISQUALDeployConsole requires portable PowerShell {0} Core x64; actual version={1}, edition={2}, x64={3}.' -f $hostResult.ExpectedVersion, $hostResult.ActualVersion, $hostResult.PSEdition, $hostResult.Is64BitProcess))
    exit 10
}

if ([string]::IsNullOrWhiteSpace($LogRoot)) { $LogRoot = $defaults.DefaultLogRoot }

try {
    $logContext = Initialize-SisqualRuntimeLog -LogRoot $LogRoot -ApprovedRoot $defaults.ApprovedLogRoot -RetentionDays $RetentionDays
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'BOOTSTRAP_STARTED'
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'HOST_VALID'
}
catch {
    [Console]::Error.WriteLine(('SISQUALDeployConsole could not initialize its text log: {0}' -f $_.Exception.Message))
    exit 11
}

$manifestPath = Join-Path $packageRoot $defaults.ManifestFileName
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    try {
        Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'MANIFEST_MISSING' -Level 'ERROR'
    }
    catch {
        [Console]::Error.WriteLine(('SISQUALDeployConsole could not write terminal log event MANIFEST_MISSING: {0}' -f $_.Exception.Message))
    }
    [Console]::Error.WriteLine('SISQUALDeployConsole package manifest is missing. Startup is blocked.')
    exit 20
}

# Phase 3A deliberately stops here. The B6.2 signer/verifier work owns the
# signature/trust implementation. Until that verifier is integrated, no module,
# catalog, credential package, HTTP adapter or engine may be loaded.
try {
    Write-SisqualBootstrapEvent -LogPath $logContext.LogPath -EventId 'INTEGRITY_VERIFIER_UNAVAILABLE' -Level 'ERROR'
}
catch {
    [Console]::Error.WriteLine(('SISQUALDeployConsole could not write terminal log event INTEGRITY_VERIFIER_UNAVAILABLE: {0}' -f $_.Exception.Message))
}
[Console]::Error.WriteLine('SISQUALDeployConsole package integrity verifier is not integrated yet. Startup is blocked.')
exit 21
