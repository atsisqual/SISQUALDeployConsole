#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
    $text = [regex]::Replace($text, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+', 'Bearer [REDACTED]')
    $assignmentPattern = '(?i)\b(password|passwd|pwd|secret|token|client[_-]?secret|authorization|cookie|api[_-]?key|connection[_-]?string)\s*[:=]\s*("[^"]*"|''[^'']*''|[^\s;]+)'
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

function Get-SisqualRuntimeLogDefaults {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        LogRoot = $script:DefaultLogRoot
        RetentionDays = $script:DefaultRetentionDays
        Prefix = $script:DefaultPrefix
    }
}

function Initialize-SisqualRuntimeLog {
    [CmdletBinding()]
    param(
        [string]$LogRoot = $script:DefaultLogRoot,
        [ValidateRange(1, 3650)]
        [int]$RetentionDays = $script:DefaultRetentionDays,
        [ValidatePattern('^[A-Za-z0-9_.-]{1,64}$')]
        [string]$Prefix = $script:DefaultPrefix
    )

    if ([string]::IsNullOrWhiteSpace($LogRoot)) {
        throw 'LogRoot cannot be empty.'
    }

    $fullRoot = [System.IO.Path]::GetFullPath($LogRoot)
    [System.IO.Directory]::CreateDirectory($fullRoot) | Out-Null

    $script:LogState = [pscustomobject]@{
        LogRoot = $fullRoot
        RetentionDays = $RetentionDays
        Prefix = $Prefix
    }

    Invoke-SisqualRuntimeLogRetention | Out-Null
    return [pscustomobject]@{
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

    $todayUtc = $ReferenceUtc.ToUniversalTime().Date
    $cutoffDate = $todayUtc.AddDays(-($script:LogState.RetentionDays - 1))
    $pattern = '^' + [regex]::Escape($script:LogState.Prefix) + '-(\d{4}-\d{2}-\d{2})\.log$'
    $removed = 0

    foreach ($file in @(Get-ChildItem -LiteralPath $script:LogState.LogRoot -File -Filter ($script:LogState.Prefix + '-*.log') -ErrorAction Stop)) {
        if ($file.Name -notmatch $pattern) {
            continue
        }

        $fileDate = [datetime]::MinValue
        $parsed = [datetime]::TryParseExact(
            $Matches[1],
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
            $removed++
        }
    }

    return $removed
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
        [System.IO.File]::AppendAllText($path, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        [System.Threading.Monitor]::Exit($script:WriteLock)
    }

    return $path
}

Export-ModuleMember -Function Get-SisqualRuntimeLogDefaults, Initialize-SisqualRuntimeLog, Invoke-SisqualRuntimeLogRetention, Write-SisqualRuntimeLog
