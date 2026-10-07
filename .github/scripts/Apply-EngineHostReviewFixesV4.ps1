#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Replace-Exact {
    param([string]$Text,[string]$Old,[string]$New,[string]$Label)
    $count = ([regex]::Matches($Text,[regex]::Escape($Old))).Count
    if ($count -ne 1) { throw ("{0}: expected exactly once, found {1}" -f $Label,$count) }
    return $Text.Replace($Old,$New)
}

$utf8 = [Text.UTF8Encoding]::new($false)
$modulePath = 'runtime/Sisqual.Runtime.EngineHost.psm1'
$m = [IO.File]::ReadAllText($modulePath)

# Add a native process-tree enumerator so an exited engine cannot leave descendants holding the redirected pipes open.
$old = @'
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
namespace Sisqual.Runtime.EngineHost {
'@
$new = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
namespace Sisqual.Runtime.EngineHost {
'@
$m = Replace-Exact $m $old $new 'extend EngineHost native imports'

$old = @'
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
}
'@
$new = @'
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

    public static class ProcessTree {
        private const uint TH32CS_SNAPPROCESS = 0x00000002;
        private static readonly IntPtr INVALID_HANDLE_VALUE = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct PROCESSENTRY32 {
            public uint dwSize;
            public uint cntUsage;
            public uint th32ProcessID;
            public IntPtr th32DefaultHeapID;
            public uint th32ModuleID;
            public uint cntThreads;
            public uint th32ParentProcessID;
            public int pcPriClassBase;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
            public string szExeFile;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool Process32First(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool Process32Next(IntPtr hSnapshot, ref PROCESSENTRY32 lppe);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr hObject);

        public static int KillDescendants(int rootProcessId) {
            var snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == INVALID_HANDLE_VALUE) return 0;
            try {
                var parentMap = new Dictionary<int, List<int>>();
                var entry = new PROCESSENTRY32();
                entry.dwSize = (uint)Marshal.SizeOf<PROCESSENTRY32>();
                if (Process32First(snapshot, ref entry)) {
                    do {
                        int parent = unchecked((int)entry.th32ParentProcessID);
                        int pid = unchecked((int)entry.th32ProcessID);
                        if (!parentMap.TryGetValue(parent, out var children)) {
                            children = new List<int>();
                            parentMap[parent] = children;
                        }
                        children.Add(pid);
                        entry.dwSize = (uint)Marshal.SizeOf<PROCESSENTRY32>();
                    } while (Process32Next(snapshot, ref entry));
                }

                var ordered = new List<int>();
                var queue = new Queue<int>();
                queue.Enqueue(rootProcessId);
                while (queue.Count > 0) {
                    int parent = queue.Dequeue();
                    if (!parentMap.TryGetValue(parent, out var children)) continue;
                    foreach (var child in children) {
                        ordered.Add(child);
                        queue.Enqueue(child);
                    }
                }

                int killed = 0;
                for (int i = ordered.Count - 1; i >= 0; i--) {
                    try {
                        using (var process = Process.GetProcessById(ordered[i])) {
                            if (!process.HasExited) {
                                process.Kill(true);
                                process.WaitForExit(2000);
                                killed++;
                            }
                        }
                    }
                    catch { }
                }
                return killed;
            }
            finally { CloseHandle(snapshot); }
        }
    }
}
'@
$m = Replace-Exact $m $old $new 'add process-tree cleanup helper'

# Add bounded stream-task waiting and descendant cleanup helpers.
$old = @'
function Get-SisqualMemberValue {
'@
$new = @'
function Wait-SisqualEngineTaskUntil {
    param([Parameter(Mandatory)][System.Threading.Tasks.Task]$Task,[Parameter(Mandatory)][datetime]$DeadlineUtc)
    while (-not $Task.IsCompleted -and [DateTime]::UtcNow -lt $DeadlineUtc) { Start-Sleep -Milliseconds 10 }
    return $Task.IsCompleted
}

function Stop-SisqualEngineDescendants {
    param([Parameter(Mandatory)][int]$RootProcessId)
    if (-not $IsWindows) { return 0 }
    try { return [Sisqual.Runtime.EngineHost.ProcessTree]::KillDescendants($RootProcessId) }
    catch { return 0 }
}

function Get-SisqualMemberValue {
'@
$m = Replace-Exact $m $old $new 'add bounded stream helpers'

# Remove caller-controlled machine-name input; require an active verified catalog session instead.
$old = @'
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][string]$CatalogMachineName,
        [Parameter(Mandatory)][object[]]$ManifestEntries,
'@
$new = @'
        [Parameter(Mandatory)][string]$CatalogPath,
        [Parameter(Mandatory)][object]$CatalogSession,
        [Parameter(Mandatory)][object[]]$ManifestEntries,
'@
$m = Replace-Exact $m $old $new 'replace CatalogMachineName with CatalogSession'

$old = @'
    if ([int](Get-SisqualMemberValue $Engine 'RequiresAdministrator' 0) -eq 1 -and -not (Test-SisqualAdministrator)) { throw 'ADMINISTRATOR_REQUIRED' }
    if (-not [string]::Equals($CatalogMachineName, $env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }
    $CatalogPath = Get-SisqualVerifiedCatalogPath -PackageRoot $PackageRoot -CatalogPath $CatalogPath -ManifestEntries $ManifestEntries
    [string[]]$normalizedLocks = @($LockKeys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
'@
$new = @'
    if ([int](Get-SisqualMemberValue $Engine 'RequiresAdministrator' 0) -eq 1 -and -not (Test-SisqualAdministrator)) { throw 'ADMINISTRATOR_REQUIRED' }
    $CatalogPath = Get-SisqualVerifiedCatalogPath -PackageRoot $PackageRoot -CatalogPath $CatalogPath -ManifestEntries $ManifestEntries
    $sessionPath = [string](Get-SisqualMemberValue $CatalogSession 'CatalogPath' '')
    if ([string]::IsNullOrWhiteSpace($sessionPath) -or -not [IO.Path]::GetFullPath($sessionPath).Equals($CatalogPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_SESSION_MISMATCH' }
    $catalogReader = Get-Command -Name 'Get-SisqualRuntimeCatalogMachineName' -Module 'Sisqual.Runtime.Catalog' -ErrorAction SilentlyContinue
    if ($null -eq $catalogReader) { throw 'CATALOG_SESSION_REQUIRED' }
    try { $catalogMachineName = [string](& $catalogReader -Session $CatalogSession) }
    catch { throw 'CATALOG_SESSION_INVALID' }
    if ([string]::IsNullOrWhiteSpace($catalogMachineName)) { throw 'CATALOG_SESSION_INVALID' }
    if (-not [string]::Equals($catalogMachineName, $env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }
    [string[]]$normalizedLocks = @($LockKeys | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
'@
$m = Replace-Exact $m $old $new 'read machine ownership from active catalog session'

# Never await redirected streams without the engine deadline; clean up orphan descendants first.
$old = @'
        $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult(); $exitCode = $process.ExitCode
        if ($stdinWriteFailed) {
'@
$new = @'
        $descendantsKilled = Stop-SisqualEngineDescendants -RootProcessId $process.Id
        $stdoutReady = Wait-SisqualEngineTaskUntil -Task $stdoutTask -DeadlineUtc $deadlineAt
        $stderrReady = Wait-SisqualEngineTaskUntil -Task $stderrTask -DeadlineUtc $deadlineAt
        if (-not $stdoutReady -or -not $stderrReady) {
            try { $process.StandardOutput.Close() } catch { }
            try { $process.StandardError.Close() } catch { }
            [void](Stop-SisqualEngineDescendants -RootProcessId $process.Id)
            return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
        try { $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult() }
        catch [IO.InvalidDataException] { throw }
        catch { return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode 1 -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        $exitCode = $process.ExitCode
        if ($descendantsKilled -gt 0) {
            return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_NO_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks
        }
        if ($stdinWriteFailed) {
'@
$m = Replace-Exact $m $old $new 'bound stdout stderr completion'

# Invalid UTF-8 is an invalid engine result, not an escaping host exception.
$old = @'
            $rawResultText = [IO.File]::ReadAllText($resultPath, [Text.UTF8Encoding]::new($false, $true))
        }
        if (Find-SisqualSecretLeak -Texts @($rawResultText,$stdout,$stderr) -Secrets $Secrets) {
'@
$new = @'
            try { $rawResultText = [IO.File]::ReadAllText($resultPath, [Text.UTF8Encoding]::new($false, $true)) }
            catch [Text.DecoderFallbackException] { return New-SisqualLoggedEngineFailureResult -OperationId $OperationId -EngineCode $engineCode -Mode $Mode -ErrorCode 'ENGINE_INVALID_RESULT' -EngineVersion $engineVersion -ExitCode $exitCode -StartedAt $started -Secrets $Secrets -PlanFingerprint $PlanFingerprint -LockKeys $normalizedLocks }
        }
        if (Find-SisqualSecretLeak -Texts @($rawResultText,$stdout,$stderr) -Secrets $Secrets) {
'@
$m = Replace-Exact $m $old $new 'map invalid UTF8 result'
[IO.File]::WriteAllText($modulePath,$m,$utf8)

# Add the narrow machine-ownership read to the existing opaque runtime catalog session.
$catalogModulePath = 'runtime/Sisqual.Runtime.Catalog.psm1'
$c = [IO.File]::ReadAllText($catalogModulePath)
if ($c -notmatch 'function Get-SisqualRuntimeCatalogMachineName') {
    $c += @'

function Get-SisqualRuntimeCatalogMachineName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Session)

    $sessionIdProperty = $Session.PSObject.Properties['SessionId']
    if ($null -eq $sessionIdProperty -or [string]::IsNullOrWhiteSpace([string]$sessionIdProperty.Value)) { throw 'Catalog session is invalid.' }
    $sessionId = [string]$sessionIdProperty.Value
    if (-not $script:CatalogSessions.ContainsKey($sessionId)) { throw 'Catalog session is not active.' }
    $entry = $script:CatalogSessions[$sessionId]
    $command = $entry.Connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT MachineName FROM dbo_ManagedServer;'
        $reader = $command.ExecuteReader()
        try {
            if (-not $reader.Read() -or $reader.IsDBNull(0)) { throw 'dbo_ManagedServer must contain exactly one MachineName.' }
            $machineName = [string]$reader.GetString(0)
            if ($reader.Read() -or [string]::IsNullOrWhiteSpace($machineName)) { throw 'dbo_ManagedServer must contain exactly one MachineName.' }
            return $machineName
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
}

Export-ModuleMember -Function Get-SisqualRuntimeCatalogMachineName
'@
}
[IO.File]::WriteAllText($catalogModulePath,$c,$utf8)

# Real runtime-catalog integration: fixture carries the machine row and proves the private-session reader.
$runtimeTestPath = 'tests/Integration/Test-RuntimeCatalog.ps1'
$r = [IO.File]::ReadAllText($runtimeTestPath)
$old = @'
INSERT INTO catalog_meta(meta_id,schema_version,server_code,source_kind,source_reference,built_at_utc,cut_rule_version)
VALUES(1,$SchemaVersion,$(ConvertTo-SqliteLiteral $ServerCode),$(ConvertTo-SqliteLiteral $SourceKind),$(ConvertTo-SqliteLiteral $SourceReference),$(ConvertTo-SqliteLiteral $BuiltAtUtc),$CutRuleVersion);
CREATE TABLE sample(code TEXT PRIMARY KEY, value TEXT NOT NULL);
'@
$new = @'
INSERT INTO catalog_meta(meta_id,schema_version,server_code,source_kind,source_reference,built_at_utc,cut_rule_version)
VALUES(1,$SchemaVersion,$(ConvertTo-SqliteLiteral $ServerCode),$(ConvertTo-SqliteLiteral $SourceKind),$(ConvertTo-SqliteLiteral $SourceReference),$(ConvertTo-SqliteLiteral $BuiltAtUtc),$CutRuleVersion);
CREATE TABLE dbo_ManagedServer(MachineName TEXT NOT NULL);
INSERT INTO dbo_ManagedServer(MachineName) VALUES('CATALOG-MACHINE');
CREATE TABLE sample(code TEXT PRIMARY KEY, value TEXT NOT NULL);
'@
$r = Replace-Exact $r $old $new 'add managed server fixture row'
$old = @'
    Test-Check 'catalog session records guarded trust evidence' ($session.VerifiedSha256 -ceq $validTrust.Sha256 -and $session.VerifiedSize -eq $validTrust.Size)
    Test-Check 'catalog session does not expose raw SQLite connection' ($null -eq $session.PSObject.Properties['Connection'])
'@
$new = @'
    Test-Check 'catalog session records guarded trust evidence' ($session.VerifiedSha256 -ceq $validTrust.Sha256 -and $session.VerifiedSize -eq $validTrust.Size)
    Test-Check 'catalog session does not expose raw SQLite connection' ($null -eq $session.PSObject.Properties['Connection'])
    Test-Check 'active verified catalog session reads machine ownership from dbo_ManagedServer' ((Get-SisqualRuntimeCatalogMachineName -Session $session) -ceq 'CATALOG-MACHINE')
    Test-Throws 'forged catalog session cannot read machine ownership' { Get-SisqualRuntimeCatalogMachineName -Session ([pscustomobject]@{ SessionId = [guid]::NewGuid().ToString('N') }) | Out-Null }
'@
$r = Replace-Exact $r $old $new 'test runtime catalog machine reader'
[IO.File]::WriteAllText($runtimeTestPath,$r,$utf8)

# Permanent test-only catalog-session stub: it models the private session registry without a SQLite dependency in Host unit tests.
$stubPath = 'tests/EngineHost/TestCatalogSessionStub.ps1'
$stub = @'
#requires -Version 7.0
Set-StrictMode -Version Latest

function Initialize-SisqualEngineHostCatalogStub {
    Remove-Module Sisqual.Runtime.Catalog -Force -ErrorAction SilentlyContinue
    $module = New-Module -Name Sisqual.Runtime.Catalog -ScriptBlock {
        $script:Sessions = @{}
        function New-SisqualTestCatalogSession {
            param([Parameter(Mandatory)][string]$CatalogPath,[Parameter(Mandatory)][string]$MachineName)
            $id = [guid]::NewGuid().ToString('N')
            $script:Sessions[$id] = [pscustomobject]@{ CatalogPath = [IO.Path]::GetFullPath($CatalogPath); MachineName = $MachineName }
            return [pscustomobject]@{ PSTypeName = 'Sisqual.Runtime.CatalogSession'; SessionId = $id; CatalogPath = [IO.Path]::GetFullPath($CatalogPath) }
        }
        function Set-SisqualTestCatalogMachineName {
            param([Parameter(Mandatory)][object]$Session,[Parameter(Mandatory)][string]$MachineName)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $script:Sessions[$id].MachineName = $MachineName
        }
        function Get-SisqualRuntimeCatalogMachineName {
            param([Parameter(Mandatory)][object]$Session)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $entry = $script:Sessions[$id]
            if (-not [IO.Path]::GetFullPath([string]$Session.CatalogPath).Equals([string]$entry.CatalogPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'Catalog session path mismatch.' }
            return [string]$entry.MachineName
        }
        Export-ModuleMember -Function New-SisqualTestCatalogSession,Set-SisqualTestCatalogMachineName,Get-SisqualRuntimeCatalogMachineName
    }
    Import-Module $module -Global -Force
}
'@
[IO.File]::WriteAllText($stubPath,$stub,$utf8)

# Main Host tests use the session stub and add descendant-pipe and ownership checks.
$testPath = 'tests/EngineHost/Test-EngineHost.ps1'
$t = [IO.File]::ReadAllText($testPath)
$old = @'
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force

$script:Passed = 0
'@
$new = @'
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
. (Join-Path $PSScriptRoot 'TestCatalogSessionStub.ps1')
Initialize-SisqualEngineHostCatalogStub

$script:Passed = 0
'@
$t = Replace-Exact $t $old $new 'load catalog session stub in host tests'
$old = @'
        Manifest = $manifest
        Class = $EngineClass
        Scenario = $Scenario
'@
$new = @'
        Manifest = $manifest
        CatalogSession = (New-SisqualTestCatalogSession -CatalogPath $catalogPath -MachineName $env:COMPUTERNAME)
        Class = $EngineClass
        Scenario = $Scenario
'@
$t = Replace-Exact $t $old $new 'add host test catalog session'
$t = $t.Replace('-CatalogMachineName $env:COMPUTERNAME -ManifestEntries','-CatalogSession $Context.CatalogSession -ManifestEntries')
$t = $t.Replace('-CatalogMachineName $env:COMPUTERNAME -ManifestEntries $timedMutable.Manifest','-CatalogSession $timedMutable.CatalogSession -ManifestEntries $timedMutable.Manifest')
$old = @'
    Check 'host does not derive target counts from result row count' ($result.summary.targetCount -eq 1 -and @($result.results).Count -eq 2 -and $result.succeeded) ([string]$result.errorMessage)

    $argsSafe = New-TestContext -Scenario 'ARGS_ENV_SAFE'
'@
$new = @'
    Check 'host does not derive target counts from result row count' ($result.summary.targetCount -eq 1 -and @($result.results).Count -eq 2 -and $result.succeeded) ([string]$result.errorMessage)

    $foreignMachine = New-TestContext
    Set-SisqualTestCatalogMachineName -Session $foreignMachine.CatalogSession -MachineName 'NOT-THIS-MACHINE'
    $foreignMachine.CatalogSession | Add-Member -NotePropertyName MachineName -NotePropertyValue $env:COMPUTERNAME -Force
    Check 'machine ownership is read from active catalog session, not caller properties' (Throws-Code { Invoke-TestHost -Context $foreignMachine } 'CATALOG_MACHINE_MISMATCH')

    $argsSafe = New-TestContext -Scenario 'ARGS_ENV_SAFE'
'@
$t = Replace-Exact $t $old $new 'add host catalog ownership regression'
$old = @'
    $killable = New-TestContext -Scenario 'HANG_IGNORE' -TimeoutSeconds 1
'@
$new = @'
    $pipeDescendant = New-TestContext -Scenario 'DESCENDANT_PIPE' -TimeoutSeconds 2
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-TestHost -Context $pipeDescendant
    $watch.Stop()
    Check 'descendant inheriting redirected pipes cannot block the host' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 6) ([string]$result.errorMessage)

    $killable = New-TestContext -Scenario 'HANG_IGNORE' -TimeoutSeconds 1
'@
$t = Replace-Exact $t $old $new 'add descendant pipe regression'
[IO.File]::WriteAllText($testPath,$t,$utf8)

# Mutation suite uses the same session registry and proves all three review gaps.
$mutationPath = 'tests/EngineHost/Test-EngineHostMutations.ps1'
$u = [IO.File]::ReadAllText($mutationPath)
$old = @'
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
$env:SISQUAL_ENGINEHOST_TEST_LOG = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-log-' + [guid]::NewGuid().ToString('N') + '.jsonl')
'@
$new = @'
Import-Module (Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1') -Force
. (Join-Path $PSScriptRoot 'TestCatalogSessionStub.ps1')
Initialize-SisqualEngineHostCatalogStub
$env:SISQUAL_ENGINEHOST_TEST_LOG = Join-Path ([IO.Path]::GetTempPath()) ('sisqual-enginehost-log-' + [guid]::NewGuid().ToString('N') + '.jsonl')
'@
$u = Replace-Exact $u $old $new 'load catalog session stub in mutations'
$old = @'
        Root = $root; Catalog = $catalog; Scenario = $Scenario
        Engine = [pscustomobject]@{ EngineCode = 'FAKE_ENGINE'; EngineVersion = 'test-1.0'; SourceFileName = $leaf; IsEnabled = 1; MinimumPowerShell = '7.0'; RequiresAdministrator = 0 }
'@
$new = @'
        Root = $root; Catalog = $catalog; Scenario = $Scenario; CatalogSession = (New-SisqualTestCatalogSession -CatalogPath $catalog -MachineName $env:COMPUTERNAME)
        Engine = [pscustomobject]@{ EngineCode = 'FAKE_ENGINE'; EngineVersion = 'test-1.0'; SourceFileName = $leaf; IsEnabled = 1; MinimumPowerShell = '7.0'; RequiresAdministrator = 0 }
'@
$u = Replace-Exact $u $old $new 'add mutation catalog session'
$old = @'
function Run {
    param([object]$Ctx, [hashtable]$Secrets = @{}, [string]$MachineName = $env:COMPUTERNAME, [string]$Mode = 'PREVIEW', [string]$PlanFingerprint = $null, [string]$Confirmation = $null, [string]$Class = 'READ_ONLY')
    Invoke-SisqualEngineHost -Engine $Ctx.Engine -Action $Ctx.Action -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogMachineName $MachineName -ManifestEntries $Ctx.Manifest -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Ctx.Scenario) -CancellationGraceSeconds 1
}
'@
$new = @'
function Run {
    param([object]$Ctx, [hashtable]$Secrets = @{}, [string]$Mode = 'PREVIEW', [string]$PlanFingerprint = $null, [string]$Confirmation = $null, [string]$Class = 'READ_ONLY')
    Invoke-SisqualEngineHost -Engine $Ctx.Engine -Action $Ctx.Action -EngineClass $Class -PackageRoot $Ctx.Root -CatalogPath $Ctx.Catalog -CatalogSession $Ctx.CatalogSession -ManifestEntries $Ctx.Manifest -Mode $Mode -InstanceCode $Ctx.Scenario -PlanFingerprint $PlanFingerprint -ConfirmationText $Confirmation -Secrets $Secrets -LockKeys @('INSTANCE:' + [string]$Ctx.Scenario) -CancellationGraceSeconds 1
}
'@
$u = Replace-Exact $u $old $new 'replace mutation Run catalog input'
$old = @'
    $ctx = New-Ctx
    Check 'mutation: foreign catalog machine is rejected' (Throws-Code { Run $ctx -MachineName 'NOT-THIS-MACHINE' } 'CATALOG_MACHINE_MISMATCH')
'@
$new = @'
    $ctx = New-Ctx
    Set-SisqualTestCatalogMachineName -Session $ctx.CatalogSession -MachineName 'NOT-THIS-MACHINE'
    $ctx.CatalogSession | Add-Member -NotePropertyName MachineName -NotePropertyValue $env:COMPUTERNAME -Force
    Check 'mutation: foreign catalog machine is rejected from authenticated session metadata' (Throws-Code { Run $ctx } 'CATALOG_MACHINE_MISMATCH')

    $ctx = New-Ctx
    $ctx.CatalogSession = [pscustomobject]@{ SessionId = [guid]::NewGuid().ToString('N'); CatalogPath = $ctx.Catalog }
    Check 'mutation: forged catalog session is rejected' (Throws-Code { Run $ctx } 'CATALOG_SESSION_INVALID')
'@
$u = Replace-Exact $u $old $new 'replace foreign machine mutation'
$u = $u.Replace('-CatalogMachineName $env:COMPUTERNAME -ManifestEntries $ctx.Manifest','-CatalogSession $ctx.CatalogSession -ManifestEntries $ctx.Manifest')
$old = @'
    $ctx = New-Ctx -Scenario 'STREAM_LIMIT'; $result = Run $ctx
    Check 'mutation: stdout above 1 MiB is bounded' ($result.errorMessage -ceq 'ENGINE_STREAM_LIMIT')
'@
$new = @'
    $ctx = New-Ctx -Scenario 'STREAM_LIMIT'; $result = Run $ctx
    Check 'mutation: stdout above 1 MiB is bounded' ($result.errorMessage -ceq 'ENGINE_STREAM_LIMIT')

    $ctx = New-Ctx -Scenario 'DESCENDANT_PIPE'; $ctx.Action.CommandTimeoutSeconds = 2
    $watch = [Diagnostics.Stopwatch]::StartNew(); $result = Run $ctx; $watch.Stop()
    Check 'mutation: inherited descendant pipe cannot block redirected stream drain' ($result.errorMessage -ceq 'ENGINE_NO_RESULT' -and $watch.Elapsed.TotalSeconds -lt 6)

    $ctx = New-Ctx -Scenario 'INVALID_UTF8_RESULT'; $result = Run $ctx
    Check 'mutation: invalid UTF-8 result becomes ENGINE_INVALID_RESULT' ($result.errorMessage -ceq 'ENGINE_INVALID_RESULT')
'@
$u = Replace-Exact $u $old $new 'add stream and UTF8 mutations'
[IO.File]::WriteAllText($mutationPath,$u,$utf8)

# Fake engine scenarios for inherited pipes and invalid UTF-8.
$fakePath = 'tests/EngineHost/FakeEngine.ps1'
$f = [IO.File]::ReadAllText($fakePath)
$old = @'
    'NO_RESULT' { exit 0 }
    'STREAM_LIMIT' { [Console]::Out.Write(('X' * (1MB + 64KB))); exit 0 }
'@
$new = @'
    'NO_RESULT' { exit 0 }
    'INVALID_UTF8_RESULT' {
        [IO.File]::WriteAllBytes([string]$request.resultPath, [byte[]](0xC3,0x28))
        exit 0
    }
    'DESCENDANT_PIPE' {
        $childInfo = [Diagnostics.ProcessStartInfo]::new()
        $childInfo.FileName = (Get-Process -Id $PID).Path
        $childInfo.UseShellExecute = $false
        $childInfo.CreateNoWindow = $true
        foreach ($argument in @('-NoLogo','-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 15')) { [void]$childInfo.ArgumentList.Add($argument) }
        [void][Diagnostics.Process]::Start($childInfo)
        Write-ResultFile $request (New-Result $request $true)
        exit 0
    }
    'STREAM_LIMIT' { [Console]::Out.Write(('X' * (1MB + 64KB))); exit 0 }
'@
$f = Replace-Exact $f $old $new 'add fake engine descendant and UTF8 scenarios'
[IO.File]::WriteAllText($fakePath,$f,$utf8)

# Source mutation anchors make the three new guards non-optional.
$sourceMutationPath = 'tests/EngineHost/Test-EngineHostSourceMutations.ps1'
$s = [IO.File]::ReadAllText($sourceMutationPath)
$old = @'
    [pscustomobject]@{ Name = 'completion summary audit'; Text = 'targetCount = [int]$result.summary.targetCount' }
)
'@
$new = @'
    [pscustomobject]@{ Name = 'completion summary audit'; Text = 'targetCount = [int]$result.summary.targetCount' },
    [pscustomobject]@{ Name = 'machine ownership comes from active catalog session'; Text = "Get-Command -Name 'Get-SisqualRuntimeCatalogMachineName' -Module 'Sisqual.Runtime.Catalog'" },
    [pscustomobject]@{ Name = 'redirected stream drain is deadline bounded'; Text = 'Wait-SisqualEngineTaskUntil -Task $stdoutTask -DeadlineUtc $deadlineAt' },
    [pscustomobject]@{ Name = 'invalid UTF8 result is mapped'; Text = 'catch [Text.DecoderFallbackException]' }
)
'@
$s = Replace-Exact $s $old $new 'add final source mutation anchors'
[IO.File]::WriteAllText($sourceMutationPath,$s,$utf8)

# Refresh the conformance README with the newly enforced boundaries.
$readmePath = 'tests/EngineHost/README.md'
$readme = [IO.File]::ReadAllText($readmePath)
$readme = $readme.Replace('aggregate composite fingerprints.','aggregate composite fingerprints, catalog-machine ownership from an active verified runtime-catalog session, deadline-bounded redirected-stream draining, and invalid UTF-8 result rejection.')
[IO.File]::WriteAllText($readmePath,$readme,$utf8)

# Prove parser and focused fake/stub Host tests before publishing. Runtime-catalog provider proof runs in its normal CI workflow.
$files = @($modulePath,$catalogModulePath,$runtimeTestPath,$stubPath,$testPath,$mutationPath,$fakePath,$sourceMutationPath)
foreach ($file in $files) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$tokens,[ref]$errors)
    if (@($errors).Count -ne 0) { throw ("Parser errors in {0}: {1}" -f $file,(@($errors).Message -join '; ')) }
}

foreach ($test in @('tests/EngineHost/Test-FakeEngineDirect.ps1','tests/EngineHost/Test-EngineHostFingerprints.ps1','tests/EngineHost/Test-EngineHost.ps1','tests/EngineHost/Test-EngineHostMutations.ps1','tests/EngineHost/Test-EngineHostSourceMutations.ps1')) {
    & pwsh -NoLogo -NoProfile -NonInteractive -File $test
    if ($LASTEXITCODE -ne 0) { throw "Focused EngineHost test failed: $test" }
}

git diff --check
Remove-Item '.github/scripts/Apply-EngineHostReviewFixesV4.ps1' -Force
Remove-Item '.github/workflows/apply-enginehost-review-fixes-v4.yml' -Force -ErrorAction SilentlyContinue
git add -A
git diff --cached --check
git commit -m 'runtime: bind engine host to verified catalog session and bounded streams'
git push origin HEAD:engine-host/adr-0008-runtime
