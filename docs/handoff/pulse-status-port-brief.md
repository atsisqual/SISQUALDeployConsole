# PULSE_STATUS port brief

**Status:** preparation for E1. Text only; no engine implementation.
**Date:** 2026-10-09
**Base:** `main@57310b0996d8c6e8ea008af7f131bec4c65efccc`.

## 1. Sources and evidence boundary

This brief uses:

- `docs/engines/PULSE_STATUS.md`;
- `docs/migration/analysis-pulse.md`, which records its source as the exact 29,516,382-byte `database/sync/ManagementSync.sql` snapshot, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, reference `9756ba956842884fabcf25b82c4fbf1d11cf56bd`, and the `PULSE_STATUS` `ops.Engine` ScriptText from that snapshot;
- `docs/decisions-log.md`, especially the 2026-10-07 `PULSE_STATUS` owner decision;
- the exact `cfg.ReviewPulseModel` SQL at the same Management Console reference;
- `tests/Fixtures/carried-schema.json` on this base commit;
- rules 6 and 7 of `docs/handoff/preflight-port-gap.md` from read-only PR #69 head `fcb46258c18ab1e3bf2ab05080bb49f5a52e6695`, because that file is not yet in `main`.

The GitHub connector cannot return the 29.5 MB snapshot ScriptText as one direct file read. The old engine flow below is therefore limited to the source-derived extraction already recorded in `docs/migration/analysis-pulse.md`. The six `cfg.ReviewPulseModel` predicates were independently checked against their exact SQL. No predicate is inferred from an issue-code name.

## 2. Old engine behavior, step by step

### Operator preview/apply

1. Accept the management SQL instance/database, optional hub code, `-Apply`, and `-CollectOnly`.
2. If no hub code is supplied, select the first enabled Pulse profile whose enabled hub instance belongs to this machine. The old engine stops when no hub is registered. The approved portable behavior changes that case to `not applicable`.
3. Run the Pulse model review. Any `ERROR` blocks before deployment work.
4. Read one deployment-plan row for the hub, then read the website-branding model/plan/assets and Pulse resources.
5. Expand the Pulse page template. Any unresolved token is an error.
6. Build the HTTPS check plan for enabled instances on the same server and in the same country as the hub, crossed with enabled HTTP policies.
7. Preview prints the hub, public URL, destination directory, collector path, scheduled-task name, interval, and endpoint count. Preview writes nothing.
8. Apply backs up the existing page, web config, logo and collector under `ConfigBackupRoot\Pulse\<timestamp>`.
9. Apply verifies resource/branding content hashes and writes branding assets, page, web config, logo and collector atomically.
10. Apply grants modify rights on the page and collector directories to the scheduled-task identity.
11. Apply registers the scheduled task using the hub IIS identity and password.
12. Apply runs one collection immediately.

### Scheduled collection

1. Read the check plan.
2. Execute one HTTPS check for each planned row; the old engine accepts the HTTP check type only.
3. Classify the response using the configured HTTP policy and timeout.
4. Call `ops.RecordPulseRun`, which updates per-check state and consecutive-failure counters and records the run.
5. Read the current snapshot through `ops.GetPulseStatusSnapshot`, including stale-state handling.
6. Write the status JSON file consumed by the Pulse page.

The portable design does not carry `ops.PulseCheckState` or `ops.PulseRun`. The approved direction is a resolved plan file, previous status file for counters/state, atomic status-file rewrite, and one text-log line per collection.

## 3. Tables and columns read by the port

Every target table/column below was checked against `tests/Fixtures/carried-schema.json`. Columns not needed by this engine are omitted.

| Table | Confirmed columns used by PULSE_STATUS |
|---|---|
| `cfg.PulseProfile` | `HubInstanceCode`, `PageTitle`, `PageDescription`, `RelativeDirectory`, `PublicUrlTemplate`, `StatusFileName`, `CollectorScriptPath`, `ScheduledTaskName`, `CollectionIntervalMinutes`, `RefreshSeconds`, `YellowFailureCount`, `RedFailureCount`, `StaleAfterSeconds`, `ScopePolicy`, `IsEnabled`, `ModifiedAt` |
| `cfg.PulseHttpPolicy` | `ApplicationCode`, `UrlTemplate`, `HttpMethod`, `HealthyStatusSpec`, `RespondingStatusSpec`, `TreatRespondingAsHealthy`, `FollowRedirects`, `TimeoutSeconds`, `RequiredForOverallOverride`, `SortOrder`, `IsEnabled`, `ModifiedAt` |
| `cfg.PulseResource` | `ResourceCode`, `ResourceKind`, `FileName`, `TextContent`, `BinaryContent`, `ContentSha256`, `IsEnabled`, `ModifiedAt` |
| `cfg.WebsiteBrandingProfile` | `ProfileCode`, `DisplayName`, `DataSourceCode`, `IsEnabled`, `ModifiedAt` |
| `cfg.WebsiteBrandingAsset` | `AssetCode`, `DisplayName`, `AssetKind`, `FileName`, `MediaType`, `Content`, `ContentSha256`, `IsRequired`, `SortOrder`, `IsEnabled`, `ModifiedAt` |
| `cfg.Application` | `ApplicationCode`, `IsEnabled` are confirmed for the Pulse model review. The exact additional applicability columns used by the old check-plan procedure are not independently extracted; see ambiguity A2. |
| `dbo.ManagedServer` | `ServerCode`, `MachineName`, `ServicesRoot`, `ConfigBackupRoot`, `IsEnabled` |
| `dbo.ManagedInstance` | `InstanceCode`, `ServerCode`, `CountryCode`, `CustomerCode`, `CustomerName`, `HostName`, `IisIdentityUserName`, `IsEnabled` |

The old `cfg.ReviewPulseModel` uses `cfg.ManagedInstanceRuntime`, including `IisIdentityPassword`. That runtime object is not the portable credential source. The port uses `dbo.ManagedInstance` for the non-secret hub identity metadata and the external credential package for the secret.

`ops.PulseCheckState` and `ops.PulseRun` are old central runtime state and are not carried into the portable catalog.

## 4. Credential input

The engine needs the hub instance IIS identity:

- catalog metadata: `IisIdentityUserName` of the hub instance;
- secret input: `IIS_IDENTITY.<HubInstanceCode>` from the credential package.

For the original `PULSE_TASK_CREDENTIAL_MISSING` predicate, the portable equivalent must preserve the intent: username must be non-empty and the matching credential must be present/decryptable to a non-empty secret. The password is never stored in the portable catalog and must never appear in logs, result rows, plan/status files or backups.

## 5. Network access

The old and approved portable behavior performs HTTPS health requests to application endpoints of enabled instances in the hub scope. The current catalog data described by the source analysis uses:

- method `GET`;
- `HealthyStatusSpec = 200-399`;
- `RespondingStatusSpec = 401,403`;
- `TreatRespondingAsHealthy = 1`;
- redirects enabled;
- timeout 12 seconds.

The 2026-10-07 owner decision requires bounded parallelism with an overall deadline shorter than the collection interval, certificate validation by default, and any certificate-validation exception to be an explicit catalog setting. The current carried `cfg.PulseHttpPolicy` columns do not expose such a certificate-policy field; see ambiguity A3. No implementation may silently disable certificate validation.

## 6. Original Pulse model issue codes and exact severities

The exact `cfg.ReviewPulseModel` source defines these six codes. All are `ERROR`.

| Code | Severity | Exact source predicate to preserve |
|---|---|---|
| `PULSE_HUB_NOT_FOUND` | `ERROR` | No enabled `cfg.PulseProfile` for the requested hub joined to an enabled hub instance and enabled managed server. Portable mapping uses the corresponding carried instance/server tables. |
| `PULSE_TASK_CREDENTIAL_MISSING` | `ERROR` | A Pulse profile exists for the hub and either the hub IIS identity username or password is empty. Portable mapping keeps the username predicate and replaces the password column with external `IIS_IDENTITY.<HubInstanceCode>` credential presence/decryption. |
| `PULSE_RESOURCE_HASH_MISMATCH` | `ERROR` | For an enabled `cfg.PulseResource`, `ContentSha256` differs from lowercase SHA-256 of `TextContent` converted to bytes when text is non-null, otherwise `BinaryContent`. |
| `PULSE_HTTP_APPLICATION_MISSING` | `ERROR` | An enabled `cfg.PulseHttpPolicy` has no enabled `cfg.Application` with the same `ApplicationCode`. |
| `PULSE_PAGE_TEMPLATE_MISSING` | `ERROR` | No enabled `cfg.PulseResource` with `ResourceCode = 'PULSE_INDEX_HTML'`. |
| `PULSE_LOGO_MISSING` | `ERROR` | No enabled `cfg.PulseResource` with `ResourceCode = 'PULSE_LOGO'`. |

The old deployment also runs the website-branding review. Existing port-gap evidence identifies five original branding issue codes, all `ERROR`:

- `WEBSITE_BRANDING_PROFILE_MISSING`;
- `WEBSITE_BRANDING_REFERENCE_MISSING`;
- `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING`;
- `WEBSITE_BRANDING_ASSET_EMPTY`;
- `WEBSITE_BRANDING_ASSET_HASH_MISMATCH`.

This brief did not independently extract the exact stored-procedure predicate for those five codes. Their predicates must not be inferred from the names; see ambiguity A1.

## 7. Port invariants from preflight rules 6 and 7

### Rule 6: full active-machine comparison set

Pulse itself has a hub target rather than the `DEPLOYMENT_PREFLIGHT` per-instance selector, but the invariant still applies to every predicate or plan calculation that compares instances:

1. Build the comparison universe from **all enabled instances of the local machine**.
2. Apply the Pulse-specific same-country scope only after the local-machine enabled set is known.
3. Never make a duplicate/conflict/model predicate accidentally depend only on the selected/reporting target.
4. If a future API selects one hub/instance for reporting, compare against the full active-machine universe first and project the resulting finding to the selected target.

This is especially important if E1 reuses shared model-review helpers for service names, Windows identities or Web Access users.

### Rule 7: resolve and confine catalog-derived paths

No filesystem existence/read/write probe is allowed before containment is proved on the resolved path. Existing path segments must resolve symlinks, junctions and other reparse points.

At minimum E1 must apply this rule to:

- `ServicesRoot` and `ServicesRoot\HostName`: the resolved instance root must remain under the resolved services root;
- the Pulse page destination from `RelativeDirectory`: the resolved page directory must remain under the approved hub instance/site root;
- `CollectorScriptPath`: resolve before probe/write and confine it to its approved root once ambiguity A4 is answered;
- Pulse resource and branding `FileName` destinations: resolve before probe/write and confine them to the page/site root defined by the exact source plan;
- backup destinations below `ConfigBackupRoot`: resolve the root and reject any escaped destination;
- any plan/status destination derived from `StatusFileName` or other catalog text.

A lexical `GetFullPath` prefix test alone is insufficient.

## 8. Approved design changes that E1 must respect

From the owner decisions already recorded:

- no Pulse profile on the machine means `not applicable`, not a deployment failure;
- scope remains same server plus same country;
- collector runs with the portable `pwsh.exe` at its current package path and apply re-registers the task;
- V1 scheduled-task identity remains the hub IIS identity;
- bounded parallelism is required; an example bound of 16 was accepted, with an overall deadline shorter than the interval;
- HTTPS certificate validation is on by default; exception requires explicit catalog configuration;
- use scheduler COM if the `ScheduledTasks` module is unavailable in PowerShell 7;
- website-branding assets remain owned by `PULSE_STATUS`, not `MANAGED_ASSETS`.

These are constraints for E1, not permission to invent missing schema or source predicates.

## 9. Ambiguities that block implementation details

### A1. Website-branding review predicates

Known: the five branding issue codes above and their `ERROR` severity.

Unknown in this brief: the exact original SQL predicate for each code.

**Question / required evidence:** extract the exact original website-branding review procedure from the snapshot before implementing any of the five checks. Until then, no per-code trigger is defined here.

### A2. Application applicability in the old Pulse check plan

The source-derived analysis says `cfg.GetPulseCheckPlan` combines enabled instances with enabled HTTP policies and uses application applicability. `ApplicationCode` and `IsEnabled` are confirmed in the carried schema, but this brief did not independently extract the exact additional `cfg.Application` applicability columns/predicate.

**Question / required evidence:** extract the exact `cfg.GetPulseCheckPlan` predicate before coding the target plan builder. Do not substitute a plausible applicability flag.

### A3. Certificate-validation exception

The owner approved an explicit catalog setting for a certificate-validation exception. The current carried `cfg.PulseHttpPolicy` schema has no certificate-validation column.

**Question for the owner/schema task:** which catalog field represents this exception? E1 must validate certificates by default and must not invent or silently add a field in the engine PR.

### A4. `CollectorScriptPath` grammar and approved root

`CollectorScriptPath` is confirmed in `cfg.PulseProfile`, but rule 7 requires a precise approved root and path grammar before the engine can safely resolve/write it.

**Question / required evidence:** is the stored value absolute, template-based or relative, and which root does the old deployment plan authorize? Extract this from the original deployment-plan procedure before implementing the write.

### A5. Branding destination mapping

`cfg.WebsiteBrandingProfile` and `cfg.WebsiteBrandingAsset` are confirmed, but this brief did not independently extract the original plan predicate that maps each `FileName` to the hub website root.

**Question / required evidence:** extract the exact branding-plan destination rule before implementing branding filesystem writes or containment tests.

## 10. Test list by original issue code

Each implemented original issue code gets its own behavior test. The trigger must be the exact source predicate, not a reconstruction from the name.

| Code | Required test |
|---|---|
| `PULSE_HUB_NOT_FOUND` | Catalog with no enabled hub/profile/server join satisfying the exact predicate; expect exactly this `ERROR` for the hub. Include a valid control case. |
| `PULSE_TASK_CREDENTIAL_MISSING` | Two cases preserving the original OR predicate: empty catalog username, and valid username with missing/empty external IIS credential. Expect this `ERROR`; marker secret must not appear anywhere. |
| `PULSE_RESOURCE_HASH_MISMATCH` | Enabled text resource and enabled binary resource whose stored SHA-256 is changed independently of content; expect this `ERROR` for the resource. Valid hashes must not trigger. |
| `PULSE_HTTP_APPLICATION_MISSING` | Enabled HTTP policy whose `ApplicationCode` has no enabled matching application; expect this `ERROR`. Disabled policy is the negative control. |
| `PULSE_PAGE_TEMPLATE_MISSING` | Remove/disable only `PULSE_INDEX_HTML`; expect this `ERROR`. |
| `PULSE_LOGO_MISSING` | Remove/disable only `PULSE_LOGO`; expect this `ERROR`. |
| `WEBSITE_BRANDING_PROFILE_MISSING` | **Blocked by A1:** write the test only after the exact original predicate is extracted. |
| `WEBSITE_BRANDING_REFERENCE_MISSING` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_ASSET_EMPTY` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_ASSET_HASH_MISMATCH` | **Blocked by A1:** exact source predicate required. |

Additional mandatory integration/security tests after the blocking source questions are answered:

- full enabled-machine instance set is used before Pulse same-country projection (rule 6);
- a selected/reporting target cannot hide a conflict in another enabled instance (rule 6);
- instance root junction escaping `ServicesRoot` is rejected before any probe;
- page/resource/branding/collector path junction or symlink escaping its approved root is rejected before any probe/write;
- a contained reparse target remains accepted;
- preview writes nothing;
- apply uses atomic writes and a restorable backup;
- bounded parallel checks respect the overall deadline;
- HTTPS certificate validation is enabled by default;
- healthy, responding-as-healthy, redirect, timeout/refused and failed responses preserve the configured status-spec semantics;
- threshold transitions at 1 and 3 consecutive failures and stale-state handling continue correctly from the previous status file;
- scheduled-task COM fallback is covered when `ScheduledTasks` is unavailable;
- marker IIS credential is absent from result, logs, plan/status files and backup artifacts;
- machine without a Pulse profile returns `not applicable`.

## 11. E1 entry gate

E1 can implement the six exact Pulse-model predicates and non-ambiguous orchestration behavior only after its PR re-reads the exact source snapshot. Before coding the five branding checks, application applicability filtering, collector destination, certificate exception or branding destination, resolve A1-A5 with source/owner evidence. If an exact predicate remains unclear, stop on that item and name the ambiguity; do not infer it from an issue code or current document wording.
