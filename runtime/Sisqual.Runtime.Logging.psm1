#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DefaultApprovedLogRoot = 'C:\SISQUALWFM\WFM.Logs'
$script:DefaultLogRoot = 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement'
$script:DefaultRetentionDays = 30
$script:DefaultPrefix = 'SISQUALDeployConsole'
$script:LogState = $null
$script:WriteLock = [object]::new()

function Protect-SisqualRuntimeLogText {
    param(
        [AllowNull()]
        [object]$Value
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $text = $text -replace "`r`n|`r|`n", '\n'

    # Header-shaped values are consumed through the end of the logical source line.
    $headerPattern = '(?i)\b(authorization|proxy-authorization|cookie|set-cookie)\s*:\s*.*?(?=\\n|$)'
    $text = [regex]::Replace($text, $headerPattern, '$1: [REDACTED]')

    # Authentication schemes may also appear in assignment-shaped text.
    $text = [regex]::Replace($text, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', '$1 [REDACTED]')

    # Accept both plain keys and common serialized forms such as {"password":"value"}.
    $sensitiveNamePattern = 'password|passwd|pwd|secret|token|client[_-]?secret|authorization|cookie|api[_-]?key|connection[_-]?string'
    $assignmentPattern = '(?i)(?:"|'')?(' + $sensitiveNamePattern + ')(?:"|'')?\s*[:=]\s*("[^"]*"|''[^'']*''|[^\s,;}\]]+)'
    $text = [regex]::Replace($text, $assignmentPattern, '$1=[REDACTED]')
    return $text
}

function Test-SisqualSensitiveLogField {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $Name -match '(?i)(secret|password|passwd|pwd|token|authorization|cookie|credential|private.?key|client.?secret|api.?key|connection.?string)'
}

function Resolve-SisqualRuntimeLogRoot {
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot,
        [Parameter(Mandatory)]
        [string]$ApprovedRoot
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        throw 'LogRoot cannot be empty.'
    }
    if ([string]::IsNullOrWhiteSpace($ApprovedRoot)) {
        throw 'ApprovedRoot cannot be empty.'
    }
    if (-not [System.IO.Path]::IsPathRooted($LogRoot) -or -not [System.IO.Path]::IsPathRooted($ApprovedRoot)) {
        throw 'LogRoot and ApprovedRoot must be absolute local paths.'
    }

    $fullRoot = [System.IO.Path]::GetFullPath($LogRoot)
    $fullApprovedRoot = [System.IO.Path]::GetFullPath($ApprovedRoot)
    if ($fullRoot.StartsWith('\\', [StringComparison]::Ordinal) -or $fullApprovedRoot.StartsWith('\\', [StringComparison]::Ordinal)) {
        throw 'UNC and device paths are not approved for runtime logs.'
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $approvedPrefix = $fullApprovedRoot.TrimEnd($separator, [System.IO.Path]::AltDirectorySeparatorChar) + $separator
    $isApprovedRoot = $fullRoot.Equals($fullApprovedRoot, [StringComparison]::OrdinalIgnoreCase)
    $isApprovedChild = $fullRoot.StartsWith($approvedPrefix, [StringComparison]::OrdinalIgnoreCase)
    if (-not $isApprovedRoot -and -not $isApprovedChild) {
        throw "LogRoot is outside the approved local log root: $fullApprovedRoot"
    }

    return [pscustomobject]@{
        LogRoot = $fullRoot
        ApprovedRoot = $fullApprovedRoot
    }
}

function Invoke-SisqualRuntimeLogRetentionCore {
    param(
        [Parameter(Mandatory)]
        [datetime]$ReferenceUtc
    )

    $reference = $ReferenceUtc.ToUniversalTime()
    $todayUtc = [DateOnly]::FromDateTime($reference)
    $cutoffDate = $todayUtc.AddDays(-($script:LogState.RetentionDays - 1))
    $pattern = '^' + [regex]::Escape($script:LogState.Prefix) + '-(\d{4}-\d{2}-\d{2})\.log$'
    $removed = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $script:LogState.LogRoot -File -Filter ($script:LogState.Prefix + '-*.log') -ErrorAction Stop)) {
        if ($file.Name -notmatch $pattern) {
            continue
        }

        $fileDate = [DateOnly]::MinValue
        $parsed = [DateOnly]::TryParseExact(
            $Matches[1],
            'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$fileDate
        )
        if (-not $parsed) {
            continue
        }

        if ($fileDate -lt $cutoffDate) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed++
        }
    }

    $script:LogState.LastRetentionUtcDate = $todayUtc
    return $removed
}

function Get-SisqualRuntimeLogDefaults {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        ApprovedRoot = $script:DefaultApprovedLogRoot
        LogRoot = $script:DefaultLogRoot
        RetentionDays = $script:DefaultRetentionDays
        Prefix = $script:DefaultPrefix
    }
}

function Initialize-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [string]$LogRoot = $script:DefaultLogRoot,
        [string]$ApprovedRoot = $script:DefaultApprovedLogRoot,
        [ValidateRange(1, 3650)]
        [int]$RetentionDays = $script:DefaultRetentionDays,
        [ValidatePattern('^[A-Za-z0-9_.-]{1,64}$')]
        [string]$Prefix = $script:DefaultPrefix
    )

    $resolved = Resolve-SisqualRuntimeLogRoot -LogRoot $LogRoot -ApprovedRoot $ApprovedRoot
    [System.IO.Directory]::CreateDirectory($resolved.ApprovedRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($resolved.LogRoot) | Out-Null

    $script:LogState = [pscustomobject]@{
        ApprovedRoot = $resolved.ApprovedRoot
        LogRoot = $resolved.LogRoot
        RetentionDays = $RetentionDays
        Prefix = $Prefix
        LastRetentionUtcDate = $null
    }

    Invoke-SisqualRuntimeLogRetention | Out-Null
    return [pscustomobject]@{
        ApprovedRoot = $script:LogState.ApprovedRoot
        LogRoot = $script:LogState.LogRoot
        RetentionDays = $script:LogState.RetentionDays
        Prefix = $script:LogState.Prefix
    }
}

function Invoke-SisqualRuntimeLogRetention {
    [CmdletBinding()]
    param(
        [datetime]$ReferenceUtc = [datetime]::UtcNow
    )

    if ($null -eq $script:LogState) {
        throw 'Runtime logging has not been initialized.'
    }

    [System.Threading.Monitor]::Enter($script:WriteLock)
    try {
        return Invoke-SisqualRuntimeLogRetentionCore -ReferenceUtc $ReferenceUtc
    }
    finally {
        [System.Threading.Monitor]::Exit($script:WriteLock)
    }
}

function Write-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Z0-9_.-]{1,64}$')]
        [string]$EventCode,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [System.Collections.IDictionary]$Properties,

        [datetime]$TimestampUtc = [datetime]::UtcNow
    )

    if ($null -eq $script:LogState) {
        throw 'Runtime logging has not been initialized.'
    }

    $timestamp = $TimestampUtc.ToUniversalTime()
    $currentUtcDate = [DateOnly]::FromDateTime($timestamp)
    $fileName = '{0}-{1}.log' -f $script:LogState.Prefix, $timestamp.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    $path = Join-Path $script:LogState.LogRoot $fileName
    $safeMessage = Protect-SisqualRuntimeLogText -Value $Message
    $parts = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $Properties) {
        foreach ($keyObject in @($Properties.Keys | Sort-Object { [string]$_ })) {
            $key = [string]$keyObject
            if ($key -notmatch '^[A-Za-z0-9_.-]{1,64}$') {
                throw "Unsafe log property name: $key"
            }

            $value = if (Test-SisqualSensitiveLogField -Name $key) {
                '[REDACTED]'
            }
            else {
                Protect-SisqualRuntimeLogText -Value $Properties[$keyObject]
            }
            $value = $value.Replace('"', '\"')
            $parts.Add(('{0}="{1}"' -f $key, $value))
        }
    }

    $line = '{0} [{1}] {2} {3}' -f $timestamp.ToString('o', [Globalization.CultureInfo]::InvariantCulture), $Level, $EventCode, $safeMessage
    if ($parts.Count -gt 0) {
        $line += ' ' + ($parts -join ' ')
    }

    [System.Threading.Monitor]::Enter($script:WriteLock)
    try {
        if ($null -eq $script:LogState.LastRetentionUtcDate -or $currentUtcDate -gt $script:LogState.LastRetentionUtcDate) {
            Invoke-SisqualRuntimeLogRetentionCore -ReferenceUtc $timestamp | Out-Null
        }
        [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        [System.Threading.Monitor]::Exit($script:WriteLock)
    }

    return $path
}

Export-ModuleMember -Function Get-SisqualRuntimeLogDefaults, Initialize-SisqualRuntimeLog, Invoke-SisqualRuntimeLogRetention, Write-SisqualRuntimeLog
