# IIS_RECONCILE -> Microsoft.Web.Administration equivalence matrix

**Status:** [PROPOSED] draft for review. Satisfies condition 1 of ADR-0006 once reviewed.
**Scope:** documentation only. No product code. No change to `docs/decisions-log.md` or `docs/roadmap.md`.

Tags: [CONFIRMED] read directly from the source or from recorded evidence;
[PROPOSED] analysis or design proposal; [PENDING] test or decision not done;
[V] can only be validated on a real server.

## 1. Source and integrity

- [CONFIRMED] Reference repo `atsisqual/SISQUALManagementConsole`, file `database/sync/ManagementSync.sql`, read only.
- [CONFIRMED] Size 29,516,382 bytes (matches the GitHub API listing, 29.5 MB). SHA-256 of the file as downloaded: `9982f088188c0cdd34522a8b34cb3db26ac9ba1196af81920e4d31d9a71ddbf1`. The sibling file `ManagementSync.sql.applied-hash` holds a different value (`8979515782...`); its algorithm and input are unknown and it was not used.
- [CONFIRMED] The file was read in parts (by statement, not as a whole). Biggest lines are `cfg.LinksPageAsset` image blobs (up to about 268 KB per line), so line-oriented tools truncate; the engine row was located by pattern and parsed as a SQL string literal.
- [CONFIRMED] `ops.Engine` row `IIS_RECONCILE` starts at line 34948: `EngineVersion` = `16.3`, `SourceFileName` = `Invoke-IISReconciliation.ps1`, `MinimumPowerShell` = `5.1`, `RequiresAdministrator` = 1, `IsEnabled` = 1, `ModifiedAt` = 2026-08-06 21:18:54.
- [CONFIRMED] `ScriptText` has 91,834 characters and 2,373 lines (CRLF). Its SHA-256 over the UTF-16LE text, after unescaping `''`, equals the stored `ScriptSha256` = `77D8B88331856B9D53A9BB438EE1C05B37AD76E971263CD6571500BEFFC4AE7C`. The extraction is therefore exact.
- [CONFIRMED] `ops.Engine_BackupIisFix` (line 41363) also holds an `IIS_RECONCILE` row labelled 16.3, but with a different text (92,471 characters, SHA-256 `89AC5C2C...`). It is a pre-fix backup table. This matrix uses `ops.Engine`.
- [CONFIRMED] Script banner: `v16.3-application-conversion-reconciliation`. Header comment: "Windows PowerShell 5.1-safe SQL-driven IIS executor; SQL-controlled topology, MWA app-pool updates, and proven HTTPS/SNI certificate reconciliation".

## 2. How the script is built today

[CONFIRMED] The v16.3 script is already a hybrid of three IIS layers:

1. WebAdministration cmdlets and the `IIS:\` provider (reads, site creation, application creation and conversion, per-location settings, pool and site start/stop).
2. `Microsoft.Web.Administration` (MWA) loaded with `Add-Type` from `System32\inetsrv` (pool create/update, auto-start providers, application auto-start, bindings, certificate assignment).
3. External executables: `netsh.exe` (http.sys certificate registry) and `appcmd.exe` (configuration backup).

Under PowerShell 7 layer 1 does not work (ADR-0006, run 37293496549: `0x8007000D`). The port therefore means moving layer 1 to MWA and keeping layer 3 as external processes.

Execution order in the script (apply mode): prerequisites; auto-start providers; site policy (`ReconcileMode`); local identities; `appcmd add backup`; directories and ACLs; pools; sites; applications; application auto-start; bindings and certificates; start and verify. The plan comes from four stored procedures in the management database: `cfg.ReviewIisDeploymentModel`, `cfg.GetIisDeploymentPlan` (row types `PREREQUISITE`, `DIRECTORY`, `APP_POOL`, `SITE`, `APPLICATION`, `BINDING`), `cfg.GetIisServiceAutoStartProviderPlan`, `cfg.GetIisApplicationAutoStartPlan`. [PENDING] Their definitions were not analysed here; under ADR-0007 (proposed) they become reads of the per-machine SQLite catalog.

## 3. Summary matrix

Coverage: **Direct** = MWA (or native PowerShell 7) does it with a close API; **Needs work** = coverable but with design work or a behaviour gap; **No equivalent** = MWA has no API, keep an external tool or another mechanism.
"Not MWA" marks operations that are not IIS configuration and run natively in PowerShell 7 or as a native tool.

| ID | Operation | Used today | MWA equivalent | Coverage | Risk |
|---|---|---|---|---|---|
| IIS-01 | Windows feature check and install | `Import-Module ServerManager`, `Get-WindowsFeature`, `Install-WindowsFeature -IncludeManagementTools` | none (MWA does not manage OS features) | No equivalent | Medium |
| IIS-02 | IIS global module check | `Get-WebGlobalModule` | `GetSection("system.webServer/globalModules")` | Direct | Low |
| IIS-03 | Load the IIS management layer | `Import-Module WebAdministration`; `Add-Type` MWA dll | `Add-Type -Path ...\inetsrv\Microsoft.Web.Administration.dll` | Direct | Low |
| IIS-04 | Service auto-start providers (read, create, update) | MWA `serviceAutoStartProviders` collection | same | Direct | Low |
| IIS-05 | Application auto-start (enabled, provider) | MWA `Application` attributes | same | Direct | Low |
| IIS-06 | Pool existence and property read | `Test-Path IIS:\AppPools`, `Get-Item`, nested provider properties | `ApplicationPools[name]` typed properties | Direct | Low |
| IIS-07 | Pool create and update, identity and password | MWA `ApplicationPools.Add`, `ProcessModel` | same | Direct | Medium |
| IIS-08 | Pool runtime state read | `Get-WebAppPoolState` | `ApplicationPool.State` | Direct | Low |
| IIS-09 | Pool start and stop with transient-error retry | `Start-WebAppPool`, `Stop-WebAppPool` | `ApplicationPool.Start()`, `.Stop()` | Direct | Medium |
| IIS-10 | WAS and W3SVC readiness wait | `Get-Service`, `Start-Service` | none needed (not MWA) | Direct | Low |
| IIS-11 | Site existence | `Test-Path IIS:\Sites\<site>` | `Sites[name]` | Direct | Low |
| IIS-12 | Site create | `New-Website` | `Sites.Add(name, "http", bindingInfo, path)` | Direct | Low |
| IIS-13 | Site root application settings (pool, protocols, physical path, preload) | `Set-WebConfigurationProperty` on `MACHINE/WEBROOT/APPHOST` xpath | `Application` and `VirtualDirectory` typed properties | Direct | Low |
| IIS-14 | Site `serverAutoStart` and log directory | `Set-ItemProperty IIS:\Sites\<site>` | `Site.ServerAutoStart`, `Site.LogFile.Directory` | Direct | Low |
| IIS-15 | Per-location authentication and default document (site) | `Set-WebConfigurationProperty -Location` | `GetSection(filter, location)` | Direct | Medium |
| IIS-16 | Site state read and start | `Get-WebsiteState`, `Start-Website` | `Site.State`, `Site.Start()` | Direct | Low |
| IIS-17 | Application lookup | `Get-WebApplication` (two-step) | `Site.Applications[path]` | Direct | Low |
| IIS-18 | Folder or virtual directory existence under a site | `Test-Path IIS:\Sites\<site>\<app>` | none direct; combine `VirtualDirectories` and `Directory.Exists` | Needs work | Medium |
| IIS-19 | Application create | `New-WebApplication` | `Site.Applications.Add(path, physicalPath)` | Direct | Low |
| IIS-20 | Convert existing folder or virtual directory to application | `ConvertTo-WebApplication -Force` | `Applications.Add` plus handling of the existing virtual directory | Needs work | High |
| IIS-21 | Application settings (pool, protocols, physical path, preload) | `Set-WebConfigurationProperty` | typed properties and attribute | Direct | Low |
| IIS-22 | Per-location authentication and default document (application) | `Set-WebConfigurationProperty -Location` | `GetSection(filter, "site/app")` | Direct | Medium |
| IIS-23 | Binding read | MWA `Site.Bindings` | same | Direct | Low |
| IIS-24 | Binding add | MWA `Bindings.Add(info, protocol)` | same | Direct | Low |
| IIS-25 | `SslFlags` update | MWA `Binding.SslFlags` | same | Direct | Medium |
| IIS-26 | Certificate resolution by SQL policy | `Get-ChildItem Cert:\LocalMachine\<store>` | `X509Store` (not MWA) | Direct | Low |
| IIS-27 | Certificate assignment to a binding | MWA `Binding.AddSslCertificate`, `netsh` fallback | same | Direct | Medium |
| IIS-28 | http.sys certificate registry (show, add, delete) | `netsh http ... sslcert` | none | No equivalent | Medium |
| IIS-29 | Central certificate store bindings (`SslFlags` bit 2) | not handled by v16.3 | `Binding.SslFlags` with CCS, no certificate hash | Needs work | High |
| IIS-30 | IIS configuration backup | `appcmd add backup`, `Copy-Item` of `inetsrv\backup` | none | No equivalent | Low |
| IIS-31 | Directory create and ACL | `New-Item`, `Get-Acl`, `Set-Acl` | none needed (not MWA) | Direct | Low |
| IIS-32 | Local pool account and `IIS_IUSRS` membership | `Get/New/Set-LocalUser`, `Get/Add-LocalGroupMember`, ADSI and `net.exe` fallbacks | none needed (not MWA) | Needs work | Medium |

Totals: 32 operations; 25 Direct, 4 Needs work (IIS-18, IIS-20, IIS-29, IIS-32), 3 No equivalent (IIS-01, IIS-28, IIS-30).
[PROPOSED] All 3 "No equivalent" cases and the 4 "Needs work" cases are covered without leaving PowerShell 7 by external tools (`netsh.exe`, `appcmd.exe`, DISM) or by plain .NET; the Windows PowerShell 5.1 child process of ADR-0006 stays as a fallback only for IIS-01 and IIS-32 if their tests fail (see section 6).

(Details, examples, gaps and missing tests follow in the next sections.)

## 4. Detail per operation

Examples are [PROPOSED] sketches for PowerShell 7 and assume `$sm = [Microsoft.Web.Administration.ServerManager]::new()` created after `Add-Type` (IIS-03) and disposed in a `finally`. They are not product code.
"Covered" means exercised by the Phase 1A-2 write spike (22 of 22 checks, windows-2022 and windows-2025, fresh IIS, [CONFIRMED] in `docs/phase1/phase1a-results.md`); everything else is [PENDING].

### 4.1 Prerequisites

**IIS-01 Windows feature check and install.** `Get-WindowsFeature` and `Install-WindowsFeature` come from the `ServerManager` module, not from IIS. MWA has no feature API.
- Options: `Import-Module ServerManager -UseWindowsPowerShell` (compatibility session); `dism.exe /online /get-featureinfo` and `/enable-feature`; or the 5.1 child process fallback of ADR-0006.
- Risk: server SKUs only; install can require a restart; the compatibility session was not tested for this module.
- Test missing: [PENDING] query and install of one feature under PowerShell 7 on a windows-2022 runner; [V] behaviour with `RestartNeeded`.

**IIS-02 Global module check.** `Get-WebGlobalModule` needs `WebAdministration`, so it must be rewritten.
```powershell
$mods = $sm.GetApplicationHostConfiguration().GetSection('system.webServer/globalModules').GetCollection()
$found = @($mods | Where-Object { $_.GetAttributeValue('name') -ieq $Name }).Count -gt 0
```
- Test missing: [PENDING] read of the collection under PowerShell 7 (collection enumeration was used for `serviceAutoStartProviders` only in the current script, not in the spike).

**IIS-03 Load the management layer.** `Import-Module WebAdministration` is dropped; keep only `Add-Type -Path "$env:windir\System32\inetsrv\Microsoft.Web.Administration.dll"`. Covered (MWA loads in PowerShell 7 on both runners).

### 4.2 Auto-start

**IIS-04 / IIS-05 Auto-start providers and application auto-start.** Already MWA (`GetSection('system.applicationHost/serviceAutoStartProviders').GetCollection()`, `CreateElement('add')`, `Application.SetAttributeValue('serviceAutoStartEnabled' | 'serviceAutoStartProvider', ...)`). No change needed beyond batching.
- Test missing: [PENDING] neither is exercised by the 1A-2 spike; run both under PowerShell 7 (create, update, idempotent re-run, `$true` and `''` values through `SetAttributeValue`).

### 4.3 Pools

**IIS-06 Read.** The 12 compared properties map one to one: `ManagedRuntimeVersion`, `ManagedPipelineMode`, `Enable32BitAppOnWin64`, `AutoStart`, `StartMode`, `QueueLength`, `ProcessModel.IdentityType` (SpecificUser = 3), `ProcessModel.UserName`, `LoadUserProfile`, `MaxProcesses`, `PingingEnabled`, plus `ProcessModel.IdleTimeout` and `Recycling.PeriodicRestart.Time` (TimeSpan, compared in minutes).
```powershell
$pool = $sm.ApplicationPools[$Name]
$idleMin = [int][Math]::Round($pool.ProcessModel.IdleTimeout.TotalMinutes)
```
- Risk: enum values come back as enums, not strings; compare with `[string]` and ignore case.
- Test missing: [PENDING] drift detection for each property on pre-existing pools [V].

**IIS-07 Create and update, identity and password.** Already MWA: `ApplicationPools.Add`, property assignment, `ProcessModel.IdentityType = SpecificUser`, `UserName`, `Password`, one `CommitChanges()` per pool. Covered by 1A-2 (208 pools).
- Risk: the password goes to `applicationHost.config` (IIS encrypts it) and passes through a plain string in memory; never log it. See finding 7.
- Test missing: ADR-0006 condition 3 [PENDING][V]: real credentials, domain and local accounts, password change on an existing pool, wrong password (pool fails to start, not at commit).

**IIS-08 State read.** `$pool.State` returns `ObjectState` (`Started`, `Starting`, `Stopped`, `Stopping`, `Unknown`).
- Test missing: [PENDING] behaviour of `State` while WAS is stopped (the provider cmdlet returned null and the script maps that to `Unknown`).

**IIS-09 Start and stop with transient-error retry.**
```powershell
try { $null = $pool.Start() } catch [System.Runtime.InteropServices.COMException] {
    if ($_.Exception.HResult -ne -2147023835) { throw }   # 0x80070425, retry
}
```
- Risk: the script detects the transient error by HResult or message text; MWA may surface it as `COMException` or `ServerManagerException`. Keep both checks.
- Test missing: [PENDING][V] start right after a WAS restart, and 200+ pools in sequence (the speed claim in the spike came from batching, not from MWA).

**IIS-10 WAS and W3SVC readiness.** `Get-Service`, `Start-Service`, `WaitForStatus` are native PowerShell 7. Not MWA. Direct, no test beyond a smoke run.

### 4.4 Sites

**IIS-11 / IIS-12 Existence and create.**
```powershell
$site = $sm.Sites[$SiteName]
if ($null -eq $site) {
    $site = $sm.Sites.Add($SiteName, 'http', "$Ip`:$Port`:$Host", $PhysicalPath)
    $site.Applications['/'].ApplicationPoolName = $PoolName
}
```
Covered by 1A-2 (8 sites). Difference to check: `New-Website` assigns the site id and starts the site; with MWA the id is assigned by `Sites.Add` and the state follows the pool. Test missing: [PENDING] id assignment next to pre-existing ids [V].

**IIS-13 Root application settings.** The xpath filters `system.applicationHost/sites/site[@name='x']/application[@path='/']` map to typed properties.
```powershell
$app = $site.Applications['/']
$app.ApplicationPoolName = $PoolName
$app.EnabledProtocols = $Protocols
$app.VirtualDirectories['/'].PhysicalPath = $PhysicalPath
$app.SetAttributeValue('preloadEnabled', $true)   # attribute; absent on very old IIS
```
Test missing: [PENDING] names with an apostrophe (the script escapes `'` in xpath; typed access does not need it, but the test must prove the same names work).

**IIS-14 Site `serverAutoStart` and log directory.** `Set-ItemProperty` becomes `$site.ServerAutoStart = $true` and `$site.LogFile.Directory = $Dir`. The current script wraps both in an empty `catch`, so failures are invisible (finding 3).

**IIS-15 / IIS-22 Per-location authentication and default document.**
```powershell
$cfg = $sm.GetApplicationHostConfiguration()
$sec = $cfg.GetSection('system.webServer/security/authentication/windowsAuthentication', "$SiteName/$AppName")
$sec.SetAttributeValue('enabled', $true)
```
Location writes go to `applicationHost.config` `<location>` elements, like the cmdlet with `-PSPath MACHINE/WEBROOT/APPHOST -Location`. Covered by 1A-2 for the simple case.
- Risk: sections locked at `applicationHost.config` (`overrideModeDefault="Deny"`) raise a COM error; today this becomes a `WARNING` row and the run continues.
- Test missing: ADR-0006 condition 2 [PENDING][V]: locked sections and inherited `web.config` conflicts on a real topology.

**IIS-16 Site state and start.** `$site.State`, `$site.Start()`. Test missing: [PENDING] start when the site binding port is in use (MWA throws at start, not at commit).

### 4.5 Applications

**IIS-17 Lookup.** `$site.Applications['/' + $Name]` (case-insensitive, leading slash). The script's two-step lookup (by name, then by trimmed path) is not needed.

**IIS-18 Folder or virtual directory existence.** The provider returns true for a physical subfolder, a virtual directory or an application. MWA only knows configured objects, so the equivalent is a combination.
```powershell
$root = $site.Applications['/']
$isVdir = $null -ne $root.VirtualDirectories['/' + $Name]
$isFolder = Test-Path -LiteralPath (Join-Path $root.VirtualDirectories['/'].PhysicalPath $Name) -PathType Container
```
- Risk: a nested path (`/a/b`) or a virtual directory with its own physical path elsewhere changes the answer.
- Test missing: [PENDING] folder only, vdir only, vdir plus folder, nested.

**IIS-19 Create.** `$app = $site.Applications.Add('/' + $Name, $PhysicalPath); $app.ApplicationPoolName = $PoolName`. Covered by 1A-2 (200 applications).

**IIS-20 Convert folder or virtual directory to application.** `ConvertTo-WebApplication -Force` has no single MWA call. Proposed procedure:
```powershell
$vd = $root.VirtualDirectories['/' + $Name]
$path = if ($vd) { $vd.PhysicalPath } else { $PhysicalPath }
if ($vd) { $root.VirtualDirectories.Remove($vd) }
$app = $site.Applications.Add('/' + $Name, $path)
$app.ApplicationPoolName = $PoolName
```
- Risk: High. Removing a virtual directory that has children, a different physical path, or per-vdir settings can lose configuration; `-Force` semantics on conflicts are not defined by MWA.
- Test missing: [PENDING][V] conversion of a plain folder, a vdir, a vdir with nested vdirs, and a vdir with its own authentication location settings. [PROPOSED] until proven, keep the 5.1 child process available for this rule only.

**IIS-21 Settings.** Same pattern as IIS-13 on the application. Covered.

### 4.6 Bindings and certificates

**IIS-23 / IIS-24 / IIS-25 Read, add, `SslFlags`.** Already MWA (`Site.Bindings`, `Bindings.Add(info, protocol)`, `Binding.SslFlags = [Enum]::ToObject(...)`). Covered by 1A-2 for http and https.
- Risk (IIS-25): changing the SNI bit moves the http.sys key from `ipport` to `hostnameport`; the old registration must be removed (see IIS-28).
- Test missing: [PENDING] flag change on an existing bound certificate; two sites sharing an IP and port with different host names.

**IIS-26 Certificate resolution.**
```powershell
$store = [System.Security.Cryptography.X509Certificates.X509Store]::new('MY', 'LocalMachine')
$store.Open('ReadOnly')
try { $cert = $store.Certificates | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) -and $_.Subject -like "CN=$Subject*" } | Sort-Object NotAfter -Descending | Select-Object -First 1 } finally { $store.Dispose() }
```
Equivalent to the `Cert:\` provider, which also works natively in PowerShell 7. Use `MY` (ADR-0006 condition 4).
- Test missing: [PENDING] wildcard and SAN-only certificates (the script matches the subject only); several valid candidates.

**IIS-27 Certificate assignment.** `$binding.AddSslCertificate($Thumbprint, 'MY')`, with the `netsh` path as fallback. Covered by 1A-2 (https binding registered in http.sys).
- Risk: the script decides the fallback by matching the error text (`does not contain a method named`, `already exists`, `183`); see finding 9.
- Test missing: [PENDING] re-assignment over an existing registration; SNI and non-SNI.

**IIS-28 http.sys registry.** `netsh http show|add|delete sslcert` with `ipport=` or `hostnameport=` and the IIS application id `{4dc3e181-e14b-4a21-b022-59fc669b0914}`. MWA cannot list or delete http.sys entries, so `netsh.exe` stays; it is an executable and does not depend on the PowerShell version. Test missing: [PENDING] parse of `netsh` output on non-English Windows [V] (the script matches the thumbprint digits only, which is locale-safe).

**IIS-29 Central certificate store bindings.** [PROPOSED] gap. The script only handles `SslFlags` bit 1 (SNI) in `Get-HttpSysSslTargetArgument`; it does not check or set bit 2 (central certificate store), the CCS provider section, or a binding without certificate hash. ADR-0006 condition 3 names CCS explicitly.
- Approach to evaluate: set `Binding.SslFlags` with bit 2 (plus bit 1) and no hash; configure the provider through the `system.webServer/centralCertProvider` section with MWA [V].
- Test missing: [PENDING][V] CCS on a real server with a file share store.

### 4.7 Backup

**IIS-30 Backup.** `appcmd.exe add backup <name>` then `Copy-Item` of `inetsrv\backup\<name>` into the run folder. MWA has no backup API; `appcmd.exe` is an executable and works the same under PowerShell 7. Alternative to decide: copy `applicationHost.config` and `administration.config` directly. Test missing: [PENDING] backup on a server with many sites (size and time).

### 4.8 Not IIS configuration, same engine

**IIS-31 Directory and ACL.** `New-Item`, `Get-Acl`, `Set-Acl` are native in PowerShell 7 (`Microsoft.PowerShell.Security`). Direct.
**IIS-32 Local pool account and `IIS_IUSRS`.** `Get-LocalUser`, `New-LocalUser`, `Set-LocalUser`, `Get-LocalGroupMember`, `Add-LocalGroupMember` belong to `Microsoft.PowerShell.LocalAccounts`; the script already falls back to ADSI (`WinNT://`) and `net.exe localgroup`. [PENDING] whether the module loads natively in PowerShell 7 on windows-2022 and windows-2025; if not, the ADSI and `net.exe` paths cover it without a 5.1 process.

## 5. Findings and gaps

1. [PROPOSED] IIS-18 and IIS-20 are the only places where the `IIS:\` provider semantics (physical folder equals item) have no MWA counterpart. They need explicit design.
2. [PROPOSED] IIS-29 (central certificate store) is not handled by v16.3 at all; confirm whether any managed site uses it before sizing the work.
3. [CONFIRMED] Silent failures: `serverAutoStart`, `logFile.directory` and `preloadEnabled` are wrapped in empty `catch`; the port should report a `WARNING` row instead, as is done for authentication sections. Decision needed (section 7).
4. [CONFIRMED] Commits are per object today (`CommitChanges` at pools, auto-start, bindings, and implicit commits in each `Set-WebConfigurationProperty`). [PROPOSED] Batch per phase (ADR-0006 condition 4) while keeping the stop-pool, change, restore-state order per pool; create a new `ServerManager` after any external change (`netsh`, `appcmd`) because a long-lived instance holds a stale view.
5. [CONFIRMED] Store name: write `MY`, compare case-insensitively (spike finding 3).
6. [CONFIRMED] The IIS application id used with `netsh` is Microsoft's standard id, not environment specific.
7. [PENDING] Pool passwords today come from `PoolIdentityPassword` in the SQL plan or from a `PSCredential` parameter. Under the owner decision of 2026-10-05 credentials come from the separate credential tool. The engine contract must receive the secret in memory only and never write it to reports or transcripts; the interface is not defined here.
8. [CONFIRMED] The reports and transcripts (`Start-Transcript`) write to a run folder; any port must ensure passwords never reach them.
9. [PROPOSED] Replace error-text matching in the certificate assignment (IIS-27) by an explicit check of the http.sys entry before assigning; the text of binder errors differs between Windows PowerShell 5.1 and PowerShell 7.
10. [PENDING][V] Behaviour of `State`, `Start()` and `Stop()` exceptions (type and HResult) in PowerShell 7 against the transient `0x80070425` case.

## 6. Missing tests

| Test | Covers | Where |
|---|---|---|
| T-01 ServerManager features under PowerShell 7 (query, install one feature) | IIS-01 | CI windows-2022 [PENDING]; restart behaviour [V] |
| T-02 `LocalAccounts` module under PowerShell 7 | IIS-32 | CI windows-2022 and windows-2025 [PENDING] |
| T-03 Global module, auto-start providers and application auto-start under PowerShell 7 | IIS-02, IIS-04, IIS-05 | CI [PENDING] |
| T-04 Application folder, vdir and nested conversion cases | IIS-18, IIS-20 | CI [PENDING]; real topology [V] |
| T-05 Locked sections and inherited `web.config` conflicts | IIS-15, IIS-22 | [V] (ADR-0006 condition 2) |
| T-06 Pool identity with real credentials, password change, wrong password | IIS-07 | [V] (ADR-0006 condition 3) |
| T-07 SNI flag change, shared IP and port, re-assignment over an existing registration | IIS-25, IIS-27, IIS-28 | CI [PENDING] |
| T-08 Central certificate store binding | IIS-29 | [V] |
| T-09 Transient `0x80070425` handling and exception types | IIS-09, IIS-16 | CI (restart WAS) [PENDING]; [V] |
| T-10 Batched commits over hundreds of pools with existing drift | IIS-06, IIS-07 | [V] (ADR-0006 conditions 2 and 4) |
| T-11 Backup size and time | IIS-30 | [V] |

## 7. Left to decide

- [PENDING] IIS-01 mechanism: compatibility session, DISM, or the 5.1 child process (decide after T-01).
- [PENDING] IIS-20 policy: convert automatically, or report and require approval when a virtual directory has children or its own settings.
- [PENDING] Whether central certificate store bindings are in V1 scope (IIS-29).
- [PENDING] Whether swallowed errors (finding 3) become warnings or failures.
- [PENDING] Backup mechanism: keep `appcmd.exe`, or copy the configuration files directly (IIS-30).
- [PENDING] Credential interface for pool passwords (finding 7), to be defined in the contracts PR and the credential tool.
- [PENDING] The four plan procedures (`cfg.GetIis*`) were not analysed; their replacement by catalog reads depends on ADR-0007 (proposed).
