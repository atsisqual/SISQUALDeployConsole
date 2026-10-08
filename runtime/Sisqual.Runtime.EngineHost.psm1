#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:EngineHostContractVersion = '0.1-proposed'
$script:RequestLimitBytes = 1MB
$script:ResultLimitBytes = 4MB
$script:StreamLimitBytes = 1MB
# The engine starts with a minimal environment, never the console's own: tokens, proxy credentials and other variables stay behind.
$script:EngineEnvironmentAllowlist = @('SystemRoot','SystemDrive','windir','ComSpec','PATHEXT','PATH','TEMP','TMP','TMPDIR','USERPROFILE','HOME','APPDATA','LOCALAPPDATA','ProgramData','ProgramFiles','ProgramFiles(x86)','ProgramW6432','CommonProgramFiles','CommonProgramFiles(x86)','CommonProgramW6432','USERNAME','USERDOMAIN','COMPUTERNAME','NUMBER_OF_PROCESSORS','PROCESSOR_ARCHITECTURE','OS','PSModulePath','LANG','LC_ALL','DOTNET_CLI_TELEMETRY_OPTOUT','POWERSHELL_TELEMETRY_OPTOUT')
$script:PreviewFingerprints = @{}
$script:TimedOutProcesses = @{}

if ($null -eq ('Sisqual.Runtime.EngineHost.BoundedReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
namespace Sisqual.Runtime.EngineHost {
    public static class BoundedReader {
        public static async Task<string> ReadAsync(StreamReader reader, int maxBytes) {
            var buffer = new char[4096];
            var builder = new StringBuilder();
            var utf8 = new UTF8Encoding(false, true);
            var bytes = 0;
            while (true) {
                var read = await reader.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
                if (read == 0) break;
                bytes += utf8.GetByteCount(buffer, 0, read);
                if (bytes > maxBytes) throw new InvalidDataException("ENGINE_STREAM_LIMIT");
                builder.Append(buffer, 0, read);
            }
            return builder.ToString();
        }
    }

    // The engine and everything it starts live in one job object and the host terminates the job. A descendant is therefore
    // identified by membership of the job and never by a process id, which Windows reuses; grandchildren whose parent already
    // died are contained too, and no state is shared between invocations. There is deliberately no kill-on-close limit: if the
    // host itself dies, a mutable engine must not be killed in the middle of a change.
    public sealed class JobContainment : IDisposable {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool QueryInformationJobObject(IntPtr job, int informationClass, IntPtr information, int informationLength, IntPtr returnLength);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);

        private const int JobObjectBasicProcessIdList = 3;
        private IntPtr handle;

        private JobContainment(IntPtr handle) { this.handle = handle; }

        public static JobContainment Create() {
            var job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new InvalidOperationException("ENGINE_CONTAINMENT_FAILED");
            return new JobContainment(job);
        }

        public void Assign(IntPtr processHandle) {
            if (handle == IntPtr.Zero || !AssignProcessToJobObject(handle, processHandle)) throw new InvalidOperationException("ENGINE_CONTAINMENT_FAILED");
        }

        // Process ids that are in the job now, or null if the list cannot be read.
        private int[] Members() {
            if (handle == IntPtr.Zero) return new int[0];
            int size = 8 + IntPtr.Size * 512;
            IntPtr buffer = Marshal.AllocHGlobal(size);
            try {
                if (!QueryInformationJobObject(handle, JobObjectBasicProcessIdList, buffer, size, IntPtr.Zero)) return null;
                int count = Marshal.ReadInt32(buffer, 4);
                var ids = new int[count];
                for (int i = 0; i < count; i++) ids[i] = unchecked((int)Marshal.ReadIntPtr(buffer, 8 + i * IntPtr.Size).ToInt64());
                return ids;
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }

        // The console host of the engine's own console (System32\conhost.exe) belongs to the engine's console, not to what the engine left
        // behind. The process id is used only to decide whether to count it; everything is terminated through the job.
        private static bool IsSystemConsoleHost(int pid) {
            try {
                using (var process = Process.GetProcessById(pid)) {
                    if (!process.ProcessName.Equals("conhost", StringComparison.OrdinalIgnoreCase)) return false;
                    var file = process.MainModule.FileName;
                    return string.Equals(Path.GetDirectoryName(file), Environment.SystemDirectory, StringComparison.OrdinalIgnoreCase);
                }
            }
            catch { return false; }
        }

        private List<string> SurvivorNames() {
            var names = new List<string>();
            var members = Members();
            if (members == null) { names.Add("unknown"); return names; }
            foreach (var pid in members) {
                if (IsSystemConsoleHost(pid)) continue;
                try { using (var process = Process.GetProcessById(pid)) names.Add(process.ProcessName); }
                catch (ArgumentException) { /* it exited after the list was read: not a survivor */ }
                catch { names.Add("unknown"); }
            }
            return names;
        }

        // Terminates every process still in the job and returns the names of the survivors. A survivor is a process that is still
        // alive after a short settling time: the engine's own console host and other helpers that are only finishing are not.
        public string[] TerminateSurvivors() {
            var deadline = DateTime.UtcNow.AddMilliseconds(500);
            List<string> names;
            while (true) {
                names = SurvivorNames();
                if (names.Count == 0 || DateTime.UtcNow >= deadline) break;
                System.Threading.Thread.Sleep(50);
            }
            TerminateAll();
            return names.ToArray();
        }

        public void TerminateAll() { if (handle != IntPtr.Zero) TerminateJobObject(handle, 1); }

        public void Dispose() {
            if (handle != IntPtr.Zero) { CloseHandle(handle); handle = IntPtr.Zero; }
        }
    }
}
'@
}

function Wait-SisqualEngineTaskUntil {
    param([Parameter(Mandatory)][System.Threading.Tasks.Task]$Task,[Parameter(Mandatory)][datetime]$DeadlineUtc)
    while (-not $Task.IsCompleted -and [DateTime]::UtcNow -lt $DeadlineUtc) { Start-Sleep -Milliseconds 10 }
    return $Task.IsCompleted
}

function New-SisqualEngineContainment {
    if (-not $IsWindows) { return $null }
    return [Sisqual.Runtime.EngineHost.JobContainment]::Create()
}

function Stop-SisqualEngineProcessTree {
    param([Parameter(Mandatory)][System.Diagnostics.Process]$Process, [AllowNull()][object]$Containment)
    if ($null -ne $Containment) { try { $Containment.TerminateAll() } catch { } }
    else { try { if (-not $Process.HasExited) { $Process.Kill($true) } } catch { } }
}

function Get-SisqualMemberValue {
    param([Parameter(Mandatory)][object]$Object, [Parameter(Mandatory)][string]$Name, [object]$Default = $null)
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $Object[$key] }
        }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-SisqualSha256Hex {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream))).ToLowerInvariant() }
    finally { $stream.Dispose() }
}

function Get-SisqualVerifiedCatalogPath {
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][object[]]$ManifestEntries
    )

    if (-not [IO.Path]::IsPathFullyQualified($PackageRoot)) { throw 'PACKAGE_ROOT_NOT_ABSOLUTE' }
    $root = [IO.Path]::GetFullPath($PackageRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $catalogEntries = @($ManifestEntries | Where-Object {
        $candidate = [string](Get-SisqualMemberValue $_ 'path' '')
        $candidate -cmatch '^catalog/catalog-[A-Za-z0-9_-]{1,60}\.db$'
    })
    if ($catalogEntries.Count -ne 1) { throw 'CATALOG_MANIFEST_ENTRY_INVALID' }

    $entry = $catalogEntries[0]
    $relativePath = [string](Get-SisqualMemberValue $entry 'path' '')
    $expectedHash = [string](Get-SisqualMemberValue $entry 'sha256' '')
    if ($expectedHash -cnotmatch '^[0-9a-f]{64}$') { throw 'CATALOG_MANIFEST_ENTRY_INVALID' }

    $expectedPath = [IO.Path]::GetFullPath((Join-Path $root ($relativePath.Replace('/',[IO.Path]::DirectorySeparatorChar))))
    $providedPath = if ([IO.Path]::IsPathFullyQualified($CatalogPath)) {
        [IO.Path]::GetFullPath($CatalogPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $root $CatalogPath))
    }
    if (-not $providedPath.Equals($expectedPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_PATH_MISMATCH' }
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) { throw 'CATALOG_FILE_MISSING' }
    if ((Get-SisqualSha256Hex $expectedPath) -cne $expectedHash) { throw 'CATALOG_HASH_MISMATCH' }

    $sizeValue = Get-SisqualMemberValue $entry 'size' $null
    if ($null -ne $sizeValue) {
        $expectedSize = [long]$sizeValue
        if ($expectedSize -lt 0 -or (Get-Item -LiteralPath $expectedPath).Length -ne $expectedSize) { throw 'CATALOG_SIZE_MISMATCH' }
    }
    return $expectedPath
}

function ConvertTo-SisqualCanonicalString {
    param([string]$Text)
    $sb = [Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        switch ($code) {
            34 { [void]$sb.Append('\"') }
            92 { [void]$sb.Append('\\') }
            8 { [void]$sb.Append('\b') }
            9 { [void]$sb.Append('\t') }
            10 { [void]$sb.Append('\n') }
            12 { [void]$sb.Append('\f') }
            13 { [void]$sb.Append('\r') }
            default {
                if ($code -lt 32 -or $code -gt 126) { [void]$sb.Append(('\u{0:x4}' -f $code)) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-SisqualCanonicalJson {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return (ConvertTo-SisqualCanonicalString $Value) }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint32] -or $Value -is [uint64]) {
        return ([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [Collections.IDictionary]) {
        [string[]]$keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $parts = foreach ($key in $keys) { (ConvertTo-SisqualCanonicalString $key) + ':' + (ConvertTo-SisqualCanonicalJson $Value[$key]) }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [Management.Automation.PSCustomObject]) {
        $table = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $table[$property.Name] = $property.Value }
        return (ConvertTo-SisqualCanonicalJson $table)
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = foreach ($item in $Value) { ConvertTo-SisqualCanonicalJson $item }
        return '[' + (@($items) -join ',') + ']'
    }
    throw ('Value of type {0} cannot be written in canonical form.' -f $Value.GetType().FullName)
}

function Get-SisqualPlanFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Plan)
    $json = ConvertTo-SisqualCanonicalJson $Plan
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}
function Get-SisqualCompositePlanFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Children)
    $ordered = @($Children | Sort-Object @{ Expression = { [int](Get-SisqualMemberValue $_ 'step' 0) } }, @{ Expression = { [string](Get-SisqualMemberValue $_ 'engineCode' '') } }, @{ Expression = { [string](Get-SisqualMemberValue $_ 'instanceCode' '') } })
    $shape = foreach ($child in $ordered) {
        [ordered]@{
            step = [int](Get-SisqualMemberValue $child 'step' 0)
            engineCode = [string](Get-SisqualMemberValue $child 'engineCode' '')
            instanceCode = [string](Get-SisqualMemberValue $child 'instanceCode' '')
            planFingerprint = [string](Get-SisqualMemberValue $child 'planFingerprint' '')
        }
    }
    return Get-SisqualPlanFingerprint @($shape)
}

function Get-SisqualSecretRepresentations {
    param([System.Collections.IDictionary]$Secrets)
    $representations = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($null -eq $Secrets) { return $representations }
    foreach ($key in $Secrets.Keys) {
        $value = [string]$Secrets[$key]
        if ([string]::IsNullOrEmpty($value)) { continue }
        [void]$representations.Add($value)
        [void]$representations.Add([Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($value)))
        [void]$representations.Add([Uri]::EscapeDataString($value))
        $jsonLiteral = ConvertTo-Json -InputObject $value -Compress
        if ($jsonLiteral.Length -ge 2 -and $jsonLiteral[0] -eq '"' -and $jsonLiteral[$jsonLiteral.Length - 1] -eq '"') {
            [void]$representations.Add($jsonLiteral.Substring(1, $jsonLiteral.Length - 2))
        }
    }
    return $representations
}

function Find-SisqualSecretLeak {
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Texts, [System.Collections.IDictionary]$Secrets)
    $representations = Get-SisqualSecretRepresentations $Secrets
    foreach ($text in $Texts) {
        if ($null -eq $text) { continue }
        foreach ($representation in $representations) {
            if ($text.Contains($representation, [StringComparison]::Ordinal)) { return $true }
        }

        # URI percent escapes are case-insensitive for their hexadecimal digits. Decode the
        # complete text once before comparison so equivalent forms such as %2F and %2f cannot
        # bypass the secret scan while preserving ordinal comparison for the secret itself.
        $decodedText = $text
        try { $decodedText = [Uri]::UnescapeDataString($text) } catch { $decodedText = $text }
        if (-not $decodedText.Equals($text, [StringComparison]::Ordinal)) {
            foreach ($representation in $representations) {
                if ($decodedText.Contains($representation, [StringComparison]::Ordinal)) { return $true }
            }
        }
    }
    return $false
}

function Find-SisqualDecodedSecretLeak {
    param([AllowNull()][object]$Value, [System.Collections.IDictionary]$Secrets)
    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return (Find-SisqualSecretLeak -Texts @([string]$Value) -Secrets $Secrets) }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) { if (Find-SisqualDecodedSecretLeak -Value $item -Secrets $Secrets) { return $true } }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) { if (Find-SisqualDecodedSecretLeak -Value $item -Secrets $Secrets) { return $true } }
        return $false
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) { if (Find-SisqualDecodedSecretLeak -Value $property.Value -Secrets $Secrets) { return $true } }
    }
    return $false
}

function New-SisqualEngineFailureResult {
    param([string]$OperationId, [string]$EngineCode, [ValidateSet('PREVIEW','APPLY')][string]$Mode, [string]$ErrorCode, [string]$EngineVersion = 'host', [int]$ExitCode = 1)
    $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    return [pscustomobject][ordered]@{
        contractVersion = $script:EngineHostContractVersion; operationId = $OperationId; engineCode = $EngineCode; engineVersion = $EngineVersion; mode = $Mode
        startedAt = $now; completedAt = $now; succeeded = $false; exitCode = $ExitCode; errorMessage = $ErrorCode
        summary = [pscustomobject][ordered]@{ targetCount = 1; succeededTargets = 0; failedTargets = 1; warningCount = 0; errorCount = 1 }
        results = @()
    }
}

function Test-SisqualEngineResultObject {
    param([Parameter(Mandatory)][object]$Result, [string]$OperationId, [string]$EngineCode, [string]$Mode)
    $required = @('contractVersion','operationId','engineCode','engineVersion','mode','startedAt','completedAt','succeeded','exitCode','summary','results')
    $allowed = @($required + @('planFingerprint','errorMessage','backup'))
    foreach ($name in $required) { if ($null -eq $Result.PSObject.Properties[$name]) { return $false } }
    foreach ($property in $Result.PSObject.Properties) { if ($allowed -cnotcontains $property.Name) { return $false } }
    foreach ($name in @('contractVersion','operationId','engineCode','engineVersion','mode','startedAt','completedAt')) {
        if ($Result.$name -isnot [string]) { return $false }
    }
    if ([string]$Result.contractVersion -cne $script:EngineHostContractVersion -or [string]$Result.operationId -cne $OperationId -or [string]$Result.engineCode -cne $EngineCode -or [string]$Result.mode -cne $Mode) { return $false }
    if ([string]$Result.operationId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $false }
    if ([string]$Result.engineCode -notmatch '^[A-Z][A-Z0-9_]{1,59}$' -or [string]$Result.engineVersion -notmatch '^[A-Za-z0-9._-]{1,40}$') { return $false }
    if ([string]$Result.mode -notin @('PREVIEW','APPLY')) { return $false }
    if ([string]$Result.startedAt -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' -or [string]$Result.completedAt -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { return $false }
    if ($Result.succeeded -isnot [bool] -or ($Result.exitCode -isnot [int] -and $Result.exitCode -isnot [long])) { return $false }
    if ($null -ne $Result.PSObject.Properties['planFingerprint'] -and ($Result.planFingerprint -isnot [string] -or $Result.planFingerprint -notmatch '^[0-9a-f]{64}$')) { return $false }
    if ($null -ne $Result.PSObject.Properties['errorMessage'] -and ($Result.errorMessage -isnot [string] -or $Result.errorMessage.Length -gt 2000)) { return $false }

    $summaryRequired = @('targetCount','succeededTargets','failedTargets','warningCount','errorCount')
    if ($null -eq $Result.summary) { return $false }
    foreach ($name in $summaryRequired) {
        if ($null -eq $Result.summary.PSObject.Properties[$name]) { return $false }
        $value = $Result.summary.$name
        if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -lt 0) { return $false }
    }
    foreach ($property in $Result.summary.PSObject.Properties) { if ($summaryRequired -cnotcontains $property.Name) { return $false } }
    $summaryTarget = [long]$Result.summary.targetCount
    $summarySucceeded = [long]$Result.summary.succeededTargets
    $summaryFailed = [long]$Result.summary.failedTargets
    if (($summarySucceeded + $summaryFailed) -gt $summaryTarget) { return $false }
    if ([bool]$Result.succeeded -and ($summaryFailed -ne 0 -or [long]$Result.summary.errorCount -ne 0)) { return $false }

    if ($null -ne $Result.PSObject.Properties['backup']) {
        $backup = $Result.backup
        if ($null -eq $backup -or $null -eq $backup.PSObject.Properties['created'] -or $backup.created -isnot [bool]) { return $false }
        $backupAllowed = @('created','name','location','sha256','restoreHint')
        foreach ($property in $backup.PSObject.Properties) { if ($backupAllowed -cnotcontains $property.Name) { return $false } }
        if ($null -ne $backup.PSObject.Properties['name'] -and ($backup.name -isnot [string] -or $backup.name.Length -gt 200)) { return $false }
        if ($null -ne $backup.PSObject.Properties['location'] -and ($backup.location -isnot [string] -or $backup.location.Length -gt 260)) { return $false }
        if ($null -ne $backup.PSObject.Properties['sha256'] -and ($backup.sha256 -isnot [string] -or $backup.sha256 -notmatch '^[0-9a-f]{64}$')) { return $false }
        if ($null -ne $backup.PSObject.Properties['restoreHint'] -and ($backup.restoreHint -isnot [string] -or $backup.restoreHint.Length -gt 500)) { return $false }
    }

    if ($Result.results -isnot [System.Collections.IEnumerable] -or $Result.results -is [string]) { return $false }
    foreach ($row in @($Result.results)) {
        if ($null -eq $row -or $row -isnot [System.Management.Automation.PSCustomObject]) { return $false }
        $rowRequired = @('timestamp','instanceCode','operationType','object','status')
        $rowAllowed = @($rowRequired + @('details'))
        foreach ($name in $rowRequired) { if ($null -eq $row.PSObject.Properties[$name]) { return $false } }
        foreach ($property in $row.PSObject.Properties) { if ($rowAllowed -cnotcontains $property.Name) { return $false } }
        foreach ($name in @('timestamp','instanceCode','operationType','object','status')) {
            if ($row.$name -isnot [string]) { return $false }
        }
        if ([string]$row.timestamp -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { return $false }
        if (([string]$row.instanceCode).Length -gt 60 -or ([string]$row.object).Length -gt 400) { return $false }
        if ([string]$row.operationType -notmatch '^[A-Z][A-Z0-9_]{1,59}$' -or [string]$row.status -notmatch '^[A-Za-z][A-Za-z0-9_]{1,59}$') { return $false }
        if ($null -ne $row.PSObject.Properties['details'] -and ($row.details -isnot [string] -or $row.details.Length -gt 2000)) { return $false }
    }
    return $true
}

function Test-SisqualEngineResultSafe {
    # Any exception while validating a result from the child means the result is invalid, never an escape from the host.
    param([object]$Result, [string]$OperationId, [string]$EngineCode, [string]$Mode, [int]$ExitCode)
    try {
        if (-not (Test-SisqualEngineResultObject $Result $OperationId $EngineCode $Mode)) { return $false }
        return ([long]$Result.exitCode -eq [long]$ExitCode)
    }
    catch { return $false }
}

function Test-SisqualAdministrator {
    if (-not $IsWindows) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { return [Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
    finally { $identity.Dispose() }
}

function New-SisqualEngineRunDirectory {
    param([Parameter(Mandatory)][string]$OperationId)
    $root = Join-Path ([IO.Path]::GetTempPath()) 'SISQUALDeployConsole\engine-runs'
    [void][IO.Directory]::CreateDirectory($root)
    $run = Join-Path $root $OperationId
    [void][IO.Directory]::CreateDirectory($run)
    if ($IsWindows) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $acl = [Security.AccessControl.DirectorySecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity.User, [Security.AccessControl.FileSystemRights]::FullControl, [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit', [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
            [System.IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($run), $acl)
        }
        finally { $identity.Dispose() }
    }
    return $run
}

function Get-SisqualManifestEngineHash {
    param([object[]]$ManifestEntries, [string]$RelativePath)
    $matches = @($ManifestEntries | Where-Object { [string]::Equals([string](Get-SisqualMemberValue $_ 'path' ''), $RelativePath, [StringComparison]::Ordinal) })
    if ($matches.Count -ne 1) { throw 'ENGINE_MANIFEST_ENTRY_INVALID' }
    $hash = [string](Get-SisqualMemberValue $matches[0] 'sha256' '')
    if ($hash -notmatch '^[0-9a-fA-F]{64}$') { throw 'ENGINE_MANIFEST_HASH_INVALID' }
    return $hash.ToLowerInvariant()
}

function Write-SisqualEngineHostLog {
    param([string]$EventCode, [string]$Message, [hashtable]$Properties, [System.Collections.IDictionary]$Secrets)
    $pieces = @($EventCode, $Message)
    foreach ($key in @($Properties.Keys)) { $pieces += ('{0}={1}' -f $key, $Properties[$key]) }
    if (Find-SisqualSecretLeak -Texts $pieces -Secrets $Secrets) { throw 'SECRET_LEAK' }
    if ($null -ne (Get-Command Write-SisqualRuntimeLog -ErrorAction SilentlyContinue)) { [void](Write-SisqualRuntimeLog -Level INFO -EventCode $EventCode -Message $Message -Properties $Properties) }
}

function New-SisqualLoggedEngineFailureResult {
    param(
        [string]$OperationId,
        [string]$EngineCode,
        [ValidateSet('PREVIEW','APPLY')][string]$Mode,
        [string]$ErrorCode,
        [string]$EngineVersion = 'host',
        [int]$ExitCode = 1,
        [datetime]$StartedAt = ([DateTime]::UtcNow),
        [System.Collections.IDictionary]$Secrets = @{},
        [AllowNull()][string]$PlanFingerprint,
        [string[]]$LockKeys = @(),
        [string]$Reason = '',
        [AllowNull()][string]$InstanceCode
    )
    $result = New-SisqualEngineFailureResult $OperationId $EngineCode $Mode $ErrorCode $EngineVersion $ExitCode
    Write-SisqualEngineHostLog -EventCode 'ENGINE.FAIL' -Message 'Engine run failed.' -Properties @{
        operationId = $OperationId; engine = $EngineCode; mode = $Mode
        durationMs = [int]([DateTime]::UtcNow - $StartedAt).TotalMilliseconds
        exitCode = $ExitCode; succeeded = $false; error = $ErrorCode; reason = $Reason; instance = [string]$InstanceCode
        planFingerprint = [string]$PlanFingerprint; locks = (@($LockKeys) -join ',')
        targetCount = [int]$result.summary.targetCount; succeededTargets = [int]$result.summary.succeededTargets
        failedTargets = [int]$result.summary.failedTargets; warningCount = [int]$result.summary.warningCount; errorCount = [int]$result.summary.errorCount
    } -Secrets $Secrets
    return $result
}

function Invoke-SisqualEngineHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Engine,
        [Parameter(Mandatory)][object]$Action,
        [Parameter(Mandatory)][ValidateSet('READ_ONLY','OBSERVATIONAL','MUTATING')][string]$EngineClass,
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][object]$CatalogSession,
        [Parameter(Mandatory)][object[]]$ManifestEntries,
        [ValidateSet('PREVIEW','APPLY')][string]$Mode = 'PREVIEW',
        [AllowNull()][string]$InstanceCode,
        [AllowNull()][string]$PlanFingerprint,
        [AllowNull()][string]$ConfirmationText,
        [System.Collections.IDictionary]$Secrets = @{},
        [string[]]$DeclaredSecretReferences = @(),
        [string[]]$LockKeys = @(),
        [string]$OperationId = ([guid]::NewGuid().ToString()),
        [string]$PwshPath = (Get-Process -Id $PID).Path,
        [int]$CancellationGraceSeconds = 30
    )

    if ($OperationId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'INVALID_OPERATION_ID' }
    $engineCode = [string](Get-SisqualMemberValue $Engine 'EngineCode' '')
    $engineVersion = [string](Get-SisqualMemberValue $Engine 'EngineVersion' '0.0.0')
    if ($engineCode -notmatch '^[A-Z][A-Z0-9_]{1,59}$') { throw 'INVALID_ENGINE_CODE' }
    if ([int](Get-SisqualMemberValue $Engine 'IsEnabled' 0) -ne 1) { throw 'ENGINE_DISABLED' }
    if ([int](Get-SisqualMemberValue $Action 'IsEnabled' 0) -ne 1) { throw 'ACTION_DISABLED' }
    $actionEngineCode = [string](Get-SisqualMemberValue $Action 'EngineCode' '')
    if ($actionEngineCode -cne $engineCode) { throw 'ACTION_ENGINE_MISMATCH' }

    $actionType = [string](Get-SisqualMemberValue $Action 'ActionType' 'ENGINE')
    if ($actionType -ceq 'SQL') { throw 'ACTION_TYPE_NOT_SUPPORTED' }
    if ($actionType -cne 'ENGINE') { throw 'ACTION_TYPE_REQUIRES_ORCHESTRATOR' }
    $modePolicy = [string](Get-SisqualMemberValue $Action 'ModePolicy' 'NONE')
    if (($modePolicy -ceq 'NONE' -or $EngineClass -ceq 'READ_ONLY') -and $Mode -cne 'PREVIEW') { throw 'READ_ONLY_APPLY_NOT_ALLOWED' }

    $requiresInstance = [int](Get-SisqualMemberValue $Action 'RequiresInstanceSelection' 0) -eq 1
    $allowAllInstances = [int](Get-SisqualMemberValue $Action 'AllowAllInstances' 0) -eq 1
    if ($requiresInstance -and [string]::IsNullOrWhiteSpace($InstanceCode) -and -not $allowAllInstances) { throw 'INSTANCE_REQUIRED' }
    if (-not $requiresInstance -and [int](Get-SisqualMemberValue $Action 'PassInstanceCode' 0) -ne 1) { $InstanceCode = $null }
    if ([string]::IsNullOrWhiteSpace($InstanceCode)) { $InstanceCode = $null }

    if ($Mode -ceq 'APPLY') {
        $expectedConfirmation = [string](Get-SisqualMemberValue $Action 'ConfirmationText' '')
        if (-not [string]::IsNullOrEmpty($expectedConfirmation) -and $ConfirmationText -cne $expectedConfirmation) { throw 'CONFIRMATION_REQUIRED' }
        if ($PlanFingerprint -notmatch '^[0-9a-f]{64}$') { throw 'PLAN_FINGERPRINT_REQUIRED' }
        $previewKey = '{0}|{1}' -f $engineCode, [string]$InstanceCode
        if (-not $script:PreviewFingerprints.ContainsKey($previewKey) -or $script:PreviewFingerprints[$previewKey] -cne $PlanFingerprint) { throw 'PLAN_CHANGED' }
    }

    $minimumPowerShell = [string](Get-SisqualMemberValue $Engine 'MinimumPowerShell' '')
    if (-not [string]::IsNullOrWhiteSpace($minimumPowerShell) -and $PSVersionTable.PSVersion -lt [version]$minimumPowerShell) { throw 'POWERSHELL_VERSION_UNAVAILABLE' }
    if ([int](Get-SisqualMemberValue $Engine 'RequiresAdministrator' 0) -eq 1 -and -not (Test-SisqualAdministrator)) { throw 'ADMINISTRATOR_REQUIRED' }
    $CatalogPath = Get-SisqualVerifiedCatalogPath -PackageRoot $PackageRoot -CatalogPath $CatalogPath -ManifestEntries $ManifestEntries
    $sessionPath = [string](Get-SisqualMemberValue $CatalogSession 'CatalogPath' '')
    if ([string]::IsNullOrWhiteSpace($sessionPath) -or -not [IO.Path]::GetFullPath($sessionPath).Equals($CatalogPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_SESSION_MISMATCH' }
    $catalogReader = Get-Command -Name 'Get-SisqualRuntimeCatalogMachineName' -Module 'Sisqual.Runtime.Catalog' -ErrorAction SilentlyContinue
    if ($null -eq $catalogReader) { throw 'CATALOG_SESSION_REQUIRED' }
    try { $catalogMachineName = [string](& $catalogReader -Session $CatalogSession) }
    catch { throw 'CATALOG_SESSION_INVALID' }
    if ([string]::IsNullOrWhiteSpace($catalogMachineName)) { throw 'CATALOG_SESSION_INVALID' }
    if (-not [string]::Equals($catalogMachineName, [Environment]::MachineName, [StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }
    # ADR-0008 item 7: a selected instance must exist and be enabled in the verified catalog, and the action must allow a selection.
    if (-not [string]::IsNullOrWhiteSpace($InstanceCode)) {
        if ([string](Get-SisqualMemberValue $Action 'InstanceSelectionPolicy' '') -ceq 'NONE') { throw 'INSTANCE_SELECTION_NOT_ALLOWED' }
        if ($InstanceCode -cnotmatch '^[A-Z0-9_-]{1,60}$') { throw 'INSTANCE_INVALID' }
        $instanceReader = Get-Command -Name 'Get-SisqualRuntimeCatalogInstance' -Module 'Sisqual.Runtime.Catalog' -ErrorAction SilentlyContinue
        if ($null -eq $instanceReader) { throw 'CATALOG_SESSION_REQUIRED' }
        try { $catalogInstance = & $instanceReader -Session $CatalogSession -InstanceCode $InstanceCode }
        catch { throw 'CATALOG_SESSION_INVALID' }
        if ($null -eq $catalogInstance) { throw 'INSTANCE_NOT_FOUND' }
        if ([int]$catalogInstance.IsEnabled -ne 1) { throw 'INSTANCE_DISABLED' }
    }
    # ADR-0008 item 3: the request carries only the credential references the engine specification declares. Anything else is a caller error and nothing is started.
    if ($null -ne $Secrets) {
        foreach ($secretReference in @($Secrets.Keys)) {
            if ([string]$secretReference -cnotmatch '^[A-Z0-9_.:-]{1,120}$' -or @($DeclaredSecretReferences) -cnotcontains [string]$secretReference) { throw 'SECRET_NOT_DECLARED' }
        }
    }
    [string[]]$normalizedLocks = @($LockKeys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)

    $engineLeaf = [string](Get-SisqualMemberValue $Engine 'SourceFileName' '')
    if ($engineLeaf -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.ps1$' -or $engineLeaf.Contains('..', [StringComparison]::Ordinal) -or $engineLeaf.Contains('\') -or $engineLeaf.Contains('/')) { throw 'ENGINE_SOURCE_FILENAME_INVALID' }
    $enginePath = Join-Path (Join-Path $PackageRoot 'engines') $engineLeaf
    if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) { throw 'ENGINE_FILE_MISSING' }
    $expectedHash = Get-SisqualManifestEngineHash $ManifestEntries ('engines/' + $engineLeaf)
    $actualHash = Get-SisqualSha256Hex $enginePath
    if ($actualHash -cne $expectedHash) { throw 'ENGINE_HASH_MISMATCH' }

    $runDirectory = New-SisqualEngineRunDirectory $OperationId
    $cancelPath = Join-Path $runDirectory 'cancel.requested'
    $resultPath = Join-Path $runDirectory 'result.json'
    $timeoutSeconds = [int](Get-SisqualMemberValue $Action 'CommandTimeoutSeconds' 0)
    if ($timeoutSeconds -le 0) { $timeoutSeconds = 900 }
    $deadline = [DateTime]::UtcNow.AddSeconds($timeoutSeconds).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $request = [ordered]@{
        contractVersion = $script:EngineHostContractVersion; operationId = $OperationId; engineCode = $engineCode; mode = $Mode
        instanceCode = if ([int](Get-SisqualMemberValue $Action 'PassInstanceCode' 0) -eq 1) { $InstanceCode } else { $null }
        catalogPath = $CatalogPath; planFingerprint = if ($Mode -ceq 'APPLY') { $PlanFingerprint } else { $null }
        deadlineUtc = $deadline; cancelPath = $cancelPath; resultPath = $resultPath; secrets = if ($null -eq $Secrets) { @{} } else { $Secrets }
    }
    $requestJson = $request | ConvertTo-Json -Compress -Depth 30
    if ([Text.UTF8Encoding]::new($false).GetByteCount($requestJson) -gt $script:RequestLimitBytes) { throw 'ENGINE_REQUEST_LIMIT' }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $PwshPath; $startInfo.UseShellExecute = $false; $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true; $startInfo.RedirectStandardOutput = $true; $startInfo.RedirectStandardError = $true
    $startInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false); $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false); $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',$enginePath)) { [void]$startInfo.ArgumentList.Add($argument) }
    $startInfo.Environment.Clear()
    foreach ($variableName in $script:EngineEnvironmentAllowlist) {
        $variableValue = [Environment]::GetEnvironmentVariable($variableName)
        if ($null -ne $variableValue) { $startInfo.Environment[$variableName] = $variableValue }
    }

    $process = [Diagnostics.Process]::new(); $process.StartInfo = $startInfo
    $started = [DateTime]::UtcNow; $keepRunDirectory = $false; $job = $null
    try {
        if (-not $process.Start()) { throw 'ENGINE_START_FAILED' }
        $job = New-SisqualEngineContainment
        if ($null -ne $job) {
            try { $job.Assign($process.Handle) }
            catch { Stop-SisqualEngineProcessTree -Process $process -Containment $null; throw 'ENGINE_CONTAINMENT_FAILED' }
        }
        $stdoutTask = [Sisqual.Runtime.EngineHost.BoundedReader]::ReadAsync($process.StandardOutput, $script:StreamLimitBytes)
        $stderrTask = [Sisqual.Runtime.EngineHost.BoundedReader]::ReadAsync($process.StandardError, $script:StreamLimitBytes)
        $deadlineAt = $started.AddSeconds($timeoutSeconds)
        $requestBytes = [Text.UTF8Encoding]::new($false).GetBytes($requestJson)
        $stdinTask = $process.StandardInput.BaseStream.WriteAsync($requestBytes, 0, $requestBytes.Length)
        $stdinClosed = $false
        $stdinWriteFailed = $false
        $cancelSignalFailed = $false
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadlineAt) {
            if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                try { [void]$stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                catch { $stdinWriteFailed = $true }
                $stdinClosed = $true
            }
            Start-Sleep -Milliseconds 10
        }
        $completed = $process.HasExited
        if (-not $completed) {
            # A cancellation signal that cannot be written (for example a directory pre-created at that path) is not a reason to stop the timeout handling.
            try { [IO.File]::WriteAllText($cancelPath, 'cancel', [Text.UTF8Encoding]::new($false)) }
            catch { $cancelSignalFailed = $true }
            $graceDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(1, $CancellationGraceSeconds))
            while (-not $process.HasExited -and [DateTime]::UtcNow -lt $graceDeadline) {
                if (-not $stdinClosed -and $stdinTask.IsCompleted) {
                    try { [void]$stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                    catch { $stdinWriteFailed = $true }
                    $stdinClosed = $true
                }
                Start-Sleep -Milliseconds 10
            }
            $completed = $process.HasExited
            if (-not $completed) {
                if ($EngineClass -ceq 'MUTATING') {
                    $keepRunDirectory = $true
                    $script:TimedOutProcesses[$OperationId] = [pscustomobject]@{ Process = $process; Job = $job; RunDirectory = $runDirectory; StdinTask = $stdinTask; StdoutTask = $stdoutTask; StderrTask = $stderrTask }
                    return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'TIMED_OUT_RUNNING' -Reason $(if ($cancelSignalFailed) { 'cancel_signal_failed' } else { '' }) -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
                }
                Stop-SisqualEngineProcessTree -Process $process -Containment $job; $process.WaitForExit()
            }
        }
        if (-not $stdinClosed) {
            if ($stdinTask.IsCompleted) {
                try { [void]$stdinTask.GetAwaiter().GetResult(); $process.StandardInput.Close() }
                catch { $stdinWriteFailed = $true }
            }
            else {
                $stdinWriteFailed = $true
                try { $process.StandardInput.Close() } catch { }
            }
            $stdinClosed = $true
        }

        $survivors = @()
        if ($null -ne $job) { $survivors = @($job.TerminateSurvivors()) }
        $descendantsKilled = $survivors.Count
        $stdoutReady = Wait-SisqualEngineTaskUntil -Task $stdoutTask -DeadlineUtc $deadlineAt
        $stderrReady = Wait-SisqualEngineTaskUntil -Task $stderrTask -DeadlineUtc $deadlineAt
        if (-not $stdoutReady -or -not $stderrReady) {
            try { $process.StandardOutput.Close() } catch { }
            try { $process.StandardError.Close() } catch { }
            Stop-SisqualEngineProcessTree -Process $process -Containment $job
            return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -Reason 'stream_deadline' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
        try { $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult() }
        catch [IO.InvalidDataException] { throw }
        catch { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        $exitCode = $process.ExitCode
        if ($descendantsKilled -gt 0) {
            return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -Reason ('descendants_killed:' + ($survivors -join ';')) -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
        if ($stdinWriteFailed) {
            return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -Reason 'stdin_write_failed' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
        $rawResultText = ''
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            $resultInfo = Get-Item -LiteralPath $resultPath
            if ($resultInfo.Length -gt $script:ResultLimitBytes) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_RESULT_LIMIT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
            try { $rawResultText = [IO.File]::ReadAllText($resultPath, [Text.UTF8Encoding]::new($false, $true)) }
            catch [Text.DecoderFallbackException] { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_INVALID_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        }
        if (Find-SisqualSecretLeak -Texts @($rawResultText,$stdout,$stderr) -Secrets $Secrets) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'SECRET_LEAK' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        if ($exitCode -notin @(0,1,2,3)) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        if ([string]::IsNullOrWhiteSpace($rawResultText)) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }

        try { $result = $rawResultText | ConvertFrom-Json -Depth 50 -DateKind String }
        catch { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_INVALID_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        if (Find-SisqualDecodedSecretLeak -Value $result -Secrets $Secrets) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'SECRET_LEAK' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        if (-not (Test-SisqualEngineResultSafe -Result $result -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ExitCode $exitCode)) { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_INVALID_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }

        if ($Mode -ceq 'PREVIEW' -and $modePolicy -ceq 'PREVIEW_APPLY') {
            if ($null -eq $result.PSObject.Properties['planFingerprint'] -or [string]$result.planFingerprint -notmatch '^[0-9a-f]{64}$') { return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_INVALID_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
            if ([bool]$result.succeeded) {
                $previewKey = '{0}|{1}' -f $engineCode, [string]$InstanceCode
                $script:PreviewFingerprints[$previewKey] = [string]$result.planFingerprint
            }
        }

        $auditPlanFingerprint = if ($null -ne $result.PSObject.Properties['planFingerprint']) { [string]$result.planFingerprint } else { [string]$PlanFingerprint }
        Write-SisqualEngineHostLog -EventCode 'ENGINE.COMPLETE' -Message 'Engine run completed.' -Properties @{
            operationId = $OperationId; engine = $engineCode; mode = $Mode; instance = [string]$InstanceCode
            durationMs = [int]([DateTime]::UtcNow - $started).TotalMilliseconds; exitCode = $exitCode; succeeded = [bool]$result.succeeded
            planFingerprint = $auditPlanFingerprint; locks = (@($normalizedLocks) -join ',')
            targetCount = [int]$result.summary.targetCount; succeededTargets = [int]$result.summary.succeededTargets
            failedTargets = [int]$result.summary.failedTargets; warningCount = [int]$result.summary.warningCount; errorCount = [int]$result.summary.errorCount
        } -Secrets $Secrets
        return $result
    }
    catch [IO.InvalidDataException] {
        Stop-SisqualEngineProcessTree -Process $process -Containment $job
        return New-SisqualLoggedEngineFailureResult -InstanceCode $InstanceCode -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_STREAM_LIMIT' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
    }
    finally {
        if (-not $keepRunDirectory) {
            if ($null -ne $process) { $process.Dispose() }
            if ($null -ne $job) { $job.Dispose() }
            if (Test-Path -LiteralPath $runDirectory) { Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

function Stop-SisqualTimedOutEngineProcess {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$OperationId)
    if (-not $script:TimedOutProcesses.ContainsKey($OperationId)) { return $false }
    $entry = $script:TimedOutProcesses[$OperationId]
    if ($PSCmdlet.ShouldProcess($OperationId, 'Terminate timed-out mutable engine process')) {
        try {
            Stop-SisqualEngineProcessTree -Process $entry.Process -Containment $entry.Job
            if (-not $entry.Process.HasExited) { $entry.Process.WaitForExit() }
        }
        finally {
            $entry.Process.Dispose()
            if ($null -ne $entry.Job) { $entry.Job.Dispose() }
            if (Test-Path -LiteralPath $entry.RunDirectory) { Remove-Item -LiteralPath $entry.RunDirectory -Recurse -Force -ErrorAction SilentlyContinue }
            [void]$script:TimedOutProcesses.Remove($OperationId)
        }
        return $true
    }
    return $false
}

Export-ModuleMember -Function @('Invoke-SisqualEngineHost','Get-SisqualPlanFingerprint','Get-SisqualCompositePlanFingerprint','Stop-SisqualTimedOutEngineProcess')
