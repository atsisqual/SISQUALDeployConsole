Set-StrictMode -Version Latest

function Get-SisqualRuntimeDefaults {
    [CmdletBinding()]
    param()

    [pscustomobject][ordered]@{
        ExpectedPowerShellVersion = '7.6.6'
        ApprovedLogRoot = 'C:\SISQUALWFM\WFM.Logs'
        DefaultLogRoot = 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement'
        RetentionDays = 30
        LogPrefix = 'SISQUALDeployConsole'
        ManifestFileName = 'package-manifest.json'
    }
}

function Test-SisqualRuntimeHost {
    [CmdletBinding()]
    param([string]$ExpectedVersion = '7.6.6')

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

function Assert-SisqualBootstrapPathNoReparse {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label contains an existing reparse point: $current"
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -ceq $current) { break }
        $current = $parent.FullName
    }
}

function Resolve-SisqualBootstrapLogRoot {
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][string]$ApprovedRoot
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot) -or [string]::IsNullOrWhiteSpace($ApprovedRoot)) {
        throw 'LogRoot and ApprovedRoot are required.'
    }
    if (-not [IO.Path]::IsPathRooted($LogRoot) -or -not [IO.Path]::IsPathRooted($ApprovedRoot)) {
        throw 'Runtime log paths must be absolute.'
    }
    if ($LogRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $ApprovedRoot.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for bootstrap logs.'
    }

    $fullRoot = [IO.Path]::GetFullPath($LogRoot)
    $fullApproved = [IO.Path]::GetFullPath($ApprovedRoot)
    if ($fullRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $fullApproved.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for bootstrap logs.'
    }

    $driveRoot = [IO.Path]::GetPathRoot($fullApproved)
    $drive = [IO.DriveInfo]::new($driveRoot)
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        throw 'Bootstrap logs require an absolute path on a fixed local drive.'
    }

    $separator = [IO.Path]::DirectorySeparatorChar
    $approvedPrefix = $fullApproved.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    if (-not $fullRoot.Equals($fullApproved, [StringComparison]::Ordinal) -and
        -not $fullRoot.StartsWith($approvedPrefix, [StringComparison]::Ordinal)) {
        throw "LogRoot is outside the approved local log root: $fullApproved"
    }

    Assert-SisqualBootstrapPathNoReparse -Path $fullApproved -Label 'ApprovedRoot'
    Assert-SisqualBootstrapPathNoReparse -Path $fullRoot -Label 'LogRoot'

    [pscustomobject]@{ LogRoot = $fullRoot; ApprovedRoot = $fullApproved }
}

function Get-SisqualDailyLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )
    Join-Path $LogRoot ('{0}-{1}.log' -f $Prefix, $NowUtc.ToString('yyyy-MM-dd'))
}

function Remove-SisqualExpiredLogs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogRoot,
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow,
        [string]$Prefix = 'SISQUALDeployConsole'
    )

    if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) { return @() }
    $cutoffDate = $NowUtc.Date.AddDays(-($RetentionDays - 1))
    $pattern = '^{0}-(\d{{4}}-\d{{2}}-\d{{2}})\.log$' -f [regex]::Escape($Prefix)
    $removed = [Collections.Generic.List[string]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $LogRoot -File -ErrorAction Stop)) {
        $match = [regex]::Match($file.Name, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success) { continue }
        $fileDate = [datetime]::MinValue
        $parsed = [datetime]::TryParseExact($match.Groups[1].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$fileDate)
        if ($parsed -and $fileDate.Date -lt $cutoffDate) {
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
        [string]$ApprovedRoot = 'C:\SISQUALWFM\WFM.Logs',
        [ValidateRange(1, 3650)][int]$RetentionDays = 30,
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    # Security validation is deliberately completed before any create/enumerate/delete/write.
    $resolved = Resolve-SisqualBootstrapLogRoot -LogRoot $LogRoot -ApprovedRoot $ApprovedRoot
    New-Item -ItemType Directory -Path $resolved.LogRoot -Force -ErrorAction Stop | Out-Null
    Assert-SisqualBootstrapPathNoReparse -Path $resolved.ApprovedRoot -Label 'ApprovedRoot'
    Assert-SisqualBootstrapPathNoReparse -Path $resolved.LogRoot -Label 'LogRoot'
    $removed = @(Remove-SisqualExpiredLogs -LogRoot $resolved.LogRoot -RetentionDays $RetentionDays -NowUtc $NowUtc)
    $logPath = Get-SisqualDailyLogPath -LogRoot $resolved.LogRoot -NowUtc $NowUtc

    [pscustomobject][ordered]@{
        ApprovedRoot = $resolved.ApprovedRoot
        LogRoot = $resolved.LogRoot
        LogPath = $logPath
        RetentionDays = $RetentionDays
        RemovedExpiredLogs = $removed
    }
}

function Write-SisqualBootstrapEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][ValidateSet('BOOTSTRAP_STARTED','HOST_VALID','MANIFEST_MISSING','INTEGRITY_VERIFIER_UNAVAILABLE','BOOTSTRAP_FATAL')][string]$EventId,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
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
