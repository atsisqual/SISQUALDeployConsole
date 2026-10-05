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
