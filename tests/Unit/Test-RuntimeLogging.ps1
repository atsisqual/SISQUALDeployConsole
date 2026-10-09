#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$modulePath = Join-Path $repo 'runtime' 'Sisqual.Runtime.Logging.psm1'
Import-Module $modulePath -Force

$script:Passed = 0
$script:Failed = 0

function Test-Check {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [bool]$Condition
    )

    if ($Condition) {
        $script:Passed++
        Write-Host "PASS  $Name"
    }
    else {
        $script:Failed++
        Write-Host "FAIL  $Name"
    }
}

function Test-Throws {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    Test-Check -Name $Name -Condition $threw
}

if (-not ('Sisqual.Runtime.Tests.DirectoryWriteProbe' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Sisqual.Runtime.Tests
{
    public static class DirectoryWriteProbe
    {
        private const uint GENERIC_WRITE = 0x40000000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint FILE_SHARE_WRITE = 0x00000002;
        private const uint FILE_SHARE_DELETE = 0x00000004;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(
            string lpFileName,
            uint dwDesiredAccess,
            uint dwShareMode,
            IntPtr lpSecurityAttributes,
            uint dwCreationDisposition,
            uint dwFlagsAndAttributes,
            IntPtr hTemplateFile);

        public static bool CanOpenForWrite(string path)
        {
            var handle = CreateFileW(
                path,
                GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
                IntPtr.Zero);
            if (handle.IsInvalid) return false;
            handle.Dispose();
            return true;
        }
    }
}
'@
}

$defaults = Get-SisqualRuntimeLogDefaults
Test-Check 'default approved root is the SISQUAL log tree' ($defaults.ApprovedRoot -ceq 'C:\SISQUALWFM\WFM.Logs')
Test-Check 'default log root matches ADR-0007' ($defaults.LogRoot -ceq 'C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement')
Test-Check 'default retention is 30 days' ($defaults.RetentionDays -eq 30)
Test-Check 'default prefix is stable' ($defaults.Prefix -ceq 'SISQUALDeployConsole')

$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-approved-' + [guid]::NewGuid().ToString('N'))
$tempRoot = Join-Path $tempBase 'console'
$outsideRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-outside-' + [guid]::NewGuid().ToString('N'))
$junctionTarget = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-runtime-junction-target-' + [guid]::NewGuid().ToString('N'))
try {
    Test-Throws 'log root outside approved root is rejected' {
        Initialize-SisqualRuntimeLog -LogRoot $outsideRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'TestLog' | Out-Null
    }
    Test-Throws 'UNC approved root is rejected' {
        Initialize-SisqualRuntimeLog -LogRoot '\\server\share\console' -ApprovedRoot '\\server\share' -RetentionDays 3 -Prefix 'TestLog' | Out-Null
    }

    New-Item -ItemType Directory -Path $tempBase, $junctionTarget -Force | Out-Null

    $caseApproved = Join-Path $tempBase 'CaseBoundary'
    New-Item -ItemType Directory -Path $caseApproved -Force | Out-Null
    $caseVariantRoot = Join-Path $tempBase 'caseboundary\logs'
    Test-Throws 'approved-root containment rejects case-distinct boundary spelling' {
        Initialize-SisqualRuntimeLog -LogRoot $caseVariantRoot -ApprovedRoot $caseApproved -RetentionDays 3 -Prefix 'CaseLog' | Out-Null
    }
    Test-Check 'case-distinct boundary rejection creates no log child' (-not (Test-Path -LiteralPath $caseVariantRoot))

    $junctionPath = Join-Path $tempBase 'junction'
    New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -Force | Out-Null
    Test-Throws 'log root through a junction is rejected before use' {
        Initialize-SisqualRuntimeLog -LogRoot (Join-Path $junctionPath 'console') -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'TestLog' | Out-Null
    }
    Remove-Item -LiteralPath $junctionPath -Force
    Test-Check 'junction target was not written by rejected initialization' (-not (Test-Path -LiteralPath (Join-Path $junctionTarget 'console')))

    $nestedRoot = Join-Path $tempBase 'guarded-create\one\two\console'
    $nestedState = Initialize-SisqualRuntimeLog -LogRoot $nestedRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'NestedLog'
    Test-Check 'guarded initialization creates nested missing directories' ((Test-Path -LiteralPath $nestedRoot -PathType Container) -and $nestedState.LogRoot -ceq [IO.Path]::GetFullPath($nestedRoot))

    $state = Initialize-SisqualRuntimeLog -LogRoot $tempRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'TestLog'
    Test-Check 'initialize creates configured directory' (Test-Path -LiteralPath $tempRoot -PathType Container)
    Test-Check 'initialize returns canonical approved root' ($state.ApprovedRoot -ceq [System.IO.Path]::GetFullPath($tempBase))
    Test-Check 'initialize returns canonical log root' ($state.LogRoot -ceq [System.IO.Path]::GetFullPath($tempRoot))
    Test-Check 'initialize returns configured retention' ($state.RetentionDays -eq 3)

    Test-Check 'directory write probe can open unguarded log root' ([Sisqual.Runtime.Tests.DirectoryWriteProbe]::CanOpenForWrite($tempRoot))
    $directoryGuard = [Sisqual.Runtime.LogNative]::GuardDirectoryTree($tempRoot)
    try {
        Test-Check 'directory guard denies concurrent write access to reparse metadata' (-not [Sisqual.Runtime.Tests.DirectoryWriteProbe]::CanOpenForWrite($tempRoot))
    }
    finally {
        $directoryGuard.Dispose()
    }

    $reference = [datetime]::SpecifyKind([datetime]'2026-10-06T12:00:00', [DateTimeKind]::Utc)
    $oldPath = Join-Path $tempRoot 'TestLog-2026-10-03.log'
    $boundaryPath = Join-Path $tempRoot 'TestLog-2026-10-04.log'
    $foreignPath = Join-Path $tempRoot 'Other-2020-01-01.log'
    [IO.File]::WriteAllText($oldPath, 'old')
    [IO.File]::WriteAllText($boundaryPath, 'keep')
    [IO.File]::WriteAllText($foreignPath, 'foreign')

    $removed = Invoke-SisqualRuntimeLogRetention -ReferenceUtc $reference
    Test-Check 'retention removes files older than the configured window' ($removed -eq 1 -and -not (Test-Path -LiteralPath $oldPath))
    Test-Check 'retention keeps the exact UTC boundary day' (Test-Path -LiteralPath $boundaryPath)
    Test-Check 'retention ignores files outside the logger prefix' (Test-Path -LiteralPath $foreignPath)

    $passwordKey = 'Pass' + 'word'
    $passwordValue = 'Top' + 'Secret'
    $jsonMarker = 'Json' + 'Marker'
    $escapedJsonMarker = 'Escaped' + 'Tail'
    $compositeJsonMarker = 'Composite' + 'Tail'
    $credentialName = 'cred' + 'ential'
    $credentialMarker = 'Credential' + 'LeakMarker'
    $privateKeyName = 'private' + '_key'
    $privateKeyMarker = 'Private' + 'KeyLeakMarker'
    $basicMarker = 'dXNl' + 'cjpwYXNz'
    $foldedMarker = 'Rm9s' + 'ZGVkQ3JlZA=='
    $jsonPayload = '{"' + $passwordKey + '":"' + $jsonMarker + '"}'
    $escapedJsonPayload = '{"' + $passwordKey + '":"prefix\"' + $escapedJsonMarker + '"}'
    $compositeJsonPayload = '{"token":["one","' + $compositeJsonMarker + '"]}'
    $message = "Starting token=abc123 Bearer xyz $credentialName=$credentialMarker $privateKeyName=$privateKeyMarker Authorization: Basic $basicMarker`n$jsonPayload`nAuthorization: Basic`r`n $foldedMarker`n$escapedJsonPayload`n$compositeJsonPayload"
    $properties = [ordered]@{
        Instance = 'DEMOES'
        Note = 'authorization=BasicValue'
        Cookie = 'session-cookie-value'
    }
    $properties[$passwordKey] = $passwordValue

    $logPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.START' -Message $message -Properties $properties -TimestampUtc $reference
    $text = [IO.File]::ReadAllText($logPath)
    Test-Check 'write creates the expected daily log file' ([IO.Path]::GetFileName($logPath) -ceq 'TestLog-2026-10-06.log')
    Test-Check 'write keeps safe context' ($text -match 'Instance="DEMOES"')
    $passwordRedactionPattern = [regex]::Escape($passwordKey) + '="\[REDACTED\]"'
    Test-Check 'write redacts sensitive property names' ($text -match $passwordRedactionPattern -and $text -match 'Cookie="\[REDACTED\]"')
    Test-Check 'write redacts token and authorization assignments' ($text -match 'token=\[REDACTED\]' -and $text -match 'authorization=\[REDACTED\]')
    Test-Check 'write redacts credential and private-key assignments' (($text -match ([regex]::Escape($credentialName) + '=\[REDACTED\]')) -and ($text -match ([regex]::Escape($privateKeyName) + '=\[REDACTED\]')))
    Test-Check 'write redacts bearer credentials' ($text -match 'Bearer \[REDACTED\]')
    $authorizationRedactionPattern = '(?i)authorization\s*(?::|=)\s*\[REDACTED\]'
    Test-Check 'write redacts complete Basic authorization header value' (($text -match $authorizationRedactionPattern) -and ($text -notmatch [regex]::Escape($basicMarker)))
    Test-Check 'write consumes folded authorization continuation credentials' ($text -notmatch [regex]::Escape($foldedMarker))
    Test-Check 'write redacts quoted sensitive JSON keys' ($text -match ([regex]::Escape($passwordKey) + '=\[REDACTED\]'))
    Test-Check 'write consumes escaped quotes inside sensitive JSON values' ($text -notmatch [regex]::Escape($escapedJsonMarker))
    Test-Check 'write consumes complete composite sensitive JSON values' ($text -notmatch [regex]::Escape($compositeJsonMarker))
    $forbidden = 'abc123|' + [regex]::Escape($passwordValue) + '|BasicValue|session-cookie-value|Bearer xyz|' + [regex]::Escape($basicMarker) + '|' + [regex]::Escape($foldedMarker) + '|' + [regex]::Escape($jsonMarker) + '|' + [regex]::Escape($escapedJsonMarker) + '|' + [regex]::Escape($compositeJsonMarker) + '|' + [regex]::Escape($credentialMarker) + '|' + [regex]::Escape($privateKeyMarker)
    Test-Check 'write does not contain supplied secret markers' ($text -notmatch $forbidden)
    Test-Check 'write normalizes embedded newlines to one physical record' (([IO.File]::ReadAllLines($logPath)).Count -eq 1)

    $bytes = [IO.File]::ReadAllBytes($logPath)
    $hasUtf8Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Test-Check 'log is UTF-8 without BOM' (-not $hasUtf8Bom)

    $escapedKeyRoot = Join-Path $tempBase 'escaped-key'
    Initialize-SisqualRuntimeLog -LogRoot $escapedKeyRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'EscapedKeyLog' | Out-Null
    $escapedKeyMarker = 'EscapedKey' + 'LeakMarker'
    $escapedKeyName = 'pass' + '\u0077' + 'ord'
    $escapedKeyPayload = '{"' + $escapedKeyName + '":"' + $escapedKeyMarker + '"}'
    $escapedKeyPath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.ESCAPEDKEY' -Message $escapedKeyPayload -TimestampUtc $reference
    $escapedKeyText = [IO.File]::ReadAllText($escapedKeyPath)
    Test-Check 'escaped JSON property names are decoded before sensitivity matching' (($escapedKeyText -notmatch [regex]::Escape($escapedKeyMarker)) -and $escapedKeyText -match 'password=\[REDACTED\]')

    $multilineRoot = Join-Path $tempBase 'multiline'
    Initialize-SisqualRuntimeLog -LogRoot $multilineRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'MultiLog' | Out-Null
    $multilineMarker = 'Multi' + 'LineSecret'
    $multilinePayload = "safe-prefix {`n  `"token`": [`n    `"one`",`n    `"$multilineMarker`"`n  ]`n}"
    $multilinePath = Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.MULTILINE' -Message $multilinePayload -TimestampUtc $reference
    $multilineText = [IO.File]::ReadAllText($multilinePath)
    Test-Check 'multiline composite sensitive JSON is redacted' ($multilineText -notmatch [regex]::Escape($multilineMarker))
    Test-Check 'safe prefix before multiline sensitive JSON remains available' ($multilineText -match 'safe-prefix')
    Test-Check 'multiline JSON redaction remains one physical record' (([IO.File]::ReadAllLines($multilinePath)).Count -eq 1)

    $wallRoot = Join-Path $tempBase 'wallclock'
    Initialize-SisqualRuntimeLog -LogRoot $wallRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'WallLog' | Out-Null
    $wallNow = [datetime]::UtcNow
    $wallKeepPath = Join-Path $wallRoot ('WallLog-' + $wallNow.AddDays(-1).ToString('yyyy-MM-dd') + '.log')
    [IO.File]::WriteAllText($wallKeepPath, 'keep')
    $futureTimestamp = $wallNow.AddYears(5)
    $futurePath = Write-SisqualRuntimeLog -Level WARN -EventCode 'RUNTIME.FUTURE' -Message 'future event' -TimestampUtc $futureTimestamp
    Test-Check 'event timestamp still controls the event log file date' ([IO.Path]::GetFileName($futurePath) -ceq ('WallLog-' + $futureTimestamp.ToString('yyyy-MM-dd') + '.log'))
    Test-Check 'future event timestamp does not drive automatic retention' (Test-Path -LiteralPath $wallKeepPath)

    $stalePath = Join-Path $wallRoot ('WallLog-' + $wallNow.AddDays(-3).ToString('yyyy-MM-dd') + '.log')
    [IO.File]::WriteAllText($stalePath, 'stale')
    $module = Get-Module Sisqual.Runtime.Logging
    & $module { $script:LogState.LastRetentionUtcDate = [DateOnly]::FromDateTime([datetime]::UtcNow.AddDays(-1)) }
    # The event is stamped with the wall clock, not with the fixed $reference date: on the day when 'today minus three days' is $reference's date, the stale file
    # and the file this write appends to are the same file, and the append would recreate the file that retention just removed.
    Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.ROLLOVER' -Message 'wall clock rollover' -TimestampUtc $wallNow | Out-Null
    Test-Check 'wall-clock UTC rollover automatically re-runs retention' (-not (Test-Path -LiteralPath $stalePath))

    $swapRoot = Join-Path $tempBase 'swap'
    Initialize-SisqualRuntimeLog -LogRoot $swapRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'SwapLog' | Out-Null
    Remove-Item -LiteralPath $swapRoot -Recurse -Force
    New-Item -ItemType Junction -Path $swapRoot -Target $junctionTarget -Force | Out-Null
    Test-Throws 'write rejects a log root replaced by a junction after initialization' {
        Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.REPARSE' -Message 'safe' -TimestampUtc $reference | Out-Null
    }
    Remove-Item -LiteralPath $swapRoot -Force
    Test-Check 'post-initialization junction target was not written' (@(Get-ChildItem -LiteralPath $junctionTarget -File -ErrorAction SilentlyContinue).Count -eq 0)

    $fileLinkRoot = Join-Path $tempBase 'filelink'
    Initialize-SisqualRuntimeLog -LogRoot $fileLinkRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'LinkLog' | Out-Null
    $linkTimestamp = [datetime]::UtcNow
    $dailyLinkPath = Join-Path $fileLinkRoot ('LinkLog-' + $linkTimestamp.ToString('yyyy-MM-dd') + '.log')
    $outsideFile = Join-Path $junctionTarget 'outside-daily.log'
    [IO.File]::WriteAllText($outsideFile, 'outside')
    New-Item -ItemType SymbolicLink -Path $dailyLinkPath -Target $outsideFile -Force | Out-Null
    Test-Throws 'write rejects an existing daily log file symbolic link' {
        Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.FILELINK' -Message 'safe' -TimestampUtc $linkTimestamp | Out-Null
    }
    Test-Check 'daily log symbolic-link target was not appended' ([IO.File]::ReadAllText($outsideFile) -ceq 'outside')
    Remove-Item -LiteralPath $dailyLinkPath -Force

    $hardLinkRoot = Join-Path $tempBase 'hardlink'
    Initialize-SisqualRuntimeLog -LogRoot $hardLinkRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'HardLog' | Out-Null
    $hardTimestamp = [datetime]::UtcNow
    $dailyHardPath = Join-Path $hardLinkRoot ('HardLog-' + $hardTimestamp.ToString('yyyy-MM-dd') + '.log')
    $outsideHardFile = Join-Path $junctionTarget 'outside-hard.log'
    [IO.File]::WriteAllText($outsideHardFile, 'outside-hard')
    New-Item -ItemType HardLink -Path $dailyHardPath -Target $outsideHardFile -Force | Out-Null
    Test-Throws 'write rejects an existing daily log file hard link' {
        Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.HARDLINK' -Message 'safe' -TimestampUtc $hardTimestamp | Out-Null
    }
    Test-Check 'daily log hard-link target was not appended' ([IO.File]::ReadAllText($outsideHardFile) -ceq 'outside-hard')
    Remove-Item -LiteralPath $dailyHardPath -Force

    $retentionLinkRoot = Join-Path $tempBase 'retention-link'
    Initialize-SisqualRuntimeLog -LogRoot $retentionLinkRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'RetentionLog' | Out-Null
    $retentionOutsideFile = Join-Path $junctionTarget 'retention-outside.log'
    [IO.File]::WriteAllText($retentionOutsideFile, 'preserve')
    $staleLinkPath = Join-Path $retentionLinkRoot 'RetentionLog-2026-10-01.log'
    New-Item -ItemType SymbolicLink -Path $staleLinkPath -Target $retentionOutsideFile -Force | Out-Null
    Test-Throws 'retention rejects a stale symbolic-link log file' {
        Invoke-SisqualRuntimeLogRetention -ReferenceUtc $reference | Out-Null
    }
    Test-Check 'retention symbolic-link target was not deleted or modified' ((Test-Path -LiteralPath $retentionOutsideFile) -and [IO.File]::ReadAllText($retentionOutsideFile) -ceq 'preserve')
    Remove-Item -LiteralPath $staleLinkPath -Force

    $retentionHardRoot = Join-Path $tempBase 'retention-hardlink'
    Initialize-SisqualRuntimeLog -LogRoot $retentionHardRoot -ApprovedRoot $tempBase -RetentionDays 3 -Prefix 'HardRetention' | Out-Null
    $retentionHardOutside = Join-Path $junctionTarget 'retention-hard-outside.log'
    [IO.File]::WriteAllText($retentionHardOutside, 'preserve-hard')
    $staleHardPath = Join-Path $retentionHardRoot 'HardRetention-2026-10-01.log'
    New-Item -ItemType HardLink -Path $staleHardPath -Target $retentionHardOutside -Force | Out-Null
    Test-Throws 'retention rejects a stale hard-linked log file' {
        Invoke-SisqualRuntimeLogRetention -ReferenceUtc $reference | Out-Null
    }
    Test-Check 'retention hard-link target was not deleted or modified' ((Test-Path -LiteralPath $retentionHardOutside) -and [IO.File]::ReadAllText($retentionHardOutside) -ceq 'preserve-hard')
    Remove-Item -LiteralPath $staleHardPath -Force

    Test-Throws 'invalid event codes are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'bad event' -Message 'x' | Out-Null }
    Test-Throws 'unsafe property names are rejected' { Write-SisqualRuntimeLog -Level INFO -EventCode 'RUNTIME.BADFIELD' -Message 'x' -Properties @{ 'bad field' = 'value' } | Out-Null }
}
finally {
    Remove-Module Sisqual.Runtime.Logging -ErrorAction SilentlyContinue
    foreach ($path in @($tempBase, $outsideRoot, $junctionTarget)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) {
    exit 1
}