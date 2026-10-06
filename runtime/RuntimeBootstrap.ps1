Set-StrictMode -Version Latest

function Get-SisqualRuntimeDefaults {
    [CmdletBinding()]
    param()

    [pscustomobject][ordered]@{
        ExpectedPowerShellVersion = '7.6.6'
        DefaultLogRoot = 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement'
        RetentionDays = 30
        LogPrefix = 'SISQUALDeployConsole'
        ManifestFileName = 'package-manifest.json'
    }
}

function Test-SisqualRuntimeHost {
    [CmdletBinding()]
    param(
        [string]$ExpectedVersion = '7.6.6'
    )

    $actualVersion = $PSVersionTable.PSVersion.ToString()
    $edition = [string]$PSVersionTable.PSEdition
    $is64Bit = [Environment]::Is64BitProcess
    $success = ($actualVersion -ceq $ExpectedVersion -and $edition -ceq 'Core' -and $is64Bit)

    [pscustomobject][ordered]@{
        Success = $success
        ExpectedVersion = $ExpectedVersion
        ActualVersion = $actualVersion
        PSEdition = $edition
        Is64BitProcess = $is64Bit
        PSHome = $PSHOME
    }
}

function Get-SisqualDailyLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )

    $name = '{0}-{1}.log' -f $Prefix, $NowUtc.ToString('yyyy-MM-dd')
    Join-Path $LogRoot $name
}

function Remove-SisqualExpiredLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )

    if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
        return @()
    }

    $cutoffDate = $NowUtc.Date.AddDays(-($RetentionDays - 1))
    $pattern = '^{0}-(\d{{4}}-\d{{2}}-\d{{2}})\.log$' -f [regex]::Escape($Prefix)
    $removed = [System.Collections.Generic.List[string]]::new()

    foreach ($file in @(Get-ChildItem -LiteralPath $LogRoot -File -ErrorAction Stop)) {
        $match = [regex]::Match($file.Name, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success) {
            continue
        }

        $fileDate = [datetime]::MinValue
        $parsed = [datetime]::TryParseExact(
            $match.Groups[1].Value,
            'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$fileDate
        )
        if (-not $parsed) {
            continue
        }

        if ($fileDate.Date -lt $cutoffDate) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            [void]$removed.Add($file.Name)
        }
    }

    return @($removed)
}

function Initialize-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    New-Item -ItemType Directory -Path $LogRoot -Force -ErrorAction Stop | Out-Null
    $removed = @(Remove-SisqualExpiredLogs -LogRoot $LogRoot -RetentionDays $RetentionDays -NowUtc $NowUtc)
    $logPath = Get-SisqualDailyLogPath -LogRoot $LogRoot -NowUtc $NowUtc

    [pscustomobject][ordered]@{
        LogRoot = (Resolve-Path -LiteralPath $LogRoot).Path
        LogPath = $logPath
        RetentionDays = $RetentionDays
        RemovedExpiredLogs = $removed
    }
}

function Write-SisqualBootstrapEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][ValidateSet(
            'BOOTSTRAP_STARTED',
            'HOST_VALID',
            'MANIFEST_MISSING',
            'INTEGRITY_VERIFIER_UNAVAILABLE',
            'BOOTSTRAP_FATAL'
        )][string]$EventId,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    $messages = @{
        BOOTSTRAP_STARTED = 'Runtime bootstrap started.'
        HOST_VALID = 'Pinned portable PowerShell host validated.'
        MANIFEST_MISSING = 'Package manifest is missing; startup is blocked.'
        INTEGRITY_VERIFIER_UNAVAILABLE = 'Package integrity verifier is not integrated yet; startup is blocked.'
        BOOTSTRAP_FATAL = 'Runtime bootstrap failed before application startup.'
    }

    $line = '{0} [{1}] {2} pid={3} {4}' -f $NowUtc.ToString('o'), $Level, $EventId, $PID, $messages[$EventId]
    Add-Content -LiteralPath $LogPath -Value $line -Encoding ascii -ErrorAction Stop
}
