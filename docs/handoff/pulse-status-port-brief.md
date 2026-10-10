# PULSE_STATUS port brief

**Status:** [PROPOSED] preparation for E1, text only; no engine implementation.
**Date:** 2026-10-09
**Verification tree:** `main@53719d23657ae1254bf42af731174e0c71edf26d`.
**Original PR base:** `main@57310b0996d8c6e8ea008af7f131bec4c65efccc`.
**Dependency:** [PENDING] PR #69 is still open. This brief depends on its `docs/handoff/preflight-port-gap.md` rules 6 and 7 and must not be integrated before #69. After #69 is integrated, merge the updated `main` into this branch and replace the PR-head citation below with the file from `main`.

## 1. Sources and evidence boundary

This brief uses:

- `docs/engines/PULSE_STATUS.md`;
- `docs/migration/analysis-pulse.md`, which records its source as the exact 29,516,382-byte `database/sync/ManagementSync.sql` snapshot, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, reference `9756ba956842884fabcf25b82c4fbf1d11cf56bd`, and the `PULSE_STATUS` `ops.Engine` ScriptText from that snapshot;
- `docs/decisions-log.md`, especially the 2026-10-07 `PULSE_STATUS` owner decision;
- the exact `cfg.ReviewPulseModel` SQL at the same Management Console reference;
- `tests/Fixtures/carried-schema.json` at `main@53719d23657ae1254bf42af731174e0c71edf26d`;
- rules 6 and 7 of `docs/handoff/preflight-port-gap.md` from open PR #69 head `bd44dec80ff0cf886d57a9aab3ce55db13040d37`. That file is not yet in `main`; this brief therefore depends on #69 until it is integrated.

The GitHub connector cannot return the 29.5 MB snapshot ScriptText as one direct file read. The old engine flow below is therefore limited to the source-derived extraction already recorded in `docs/migration/analysis-pulse.md`. The six `cfg.ReviewPulseModel` predicates were independently checked against their exact SQL. No predicate is inferred from an issue-code name.

The portable catalog column inventory in section 3 was rechecked against `tests/Fixtures/carried-schema.json` on the verification tree. What is **not** confirmed by that schema check is also called out explicitly: the exact `cfg.GetPulseCheckPlan` applicability predicate, the exact website-branding review predicates, the catalog field for the approved certificate exception, the authorized root/grammar for `CollectorScriptPath`, and the exact branding destination mapping.

## 2. Old engine behavior, step by step

### Operator preview/apply

1. Accept the management SQL instance/database, optional hub code, `-Apply`, and `-CollectOnly`.
2. If no hub code is supplied, select the first enabled Pulse profile whose enabled hub instance belongs to this machine. The old engine stops when no hub is registered. The approved portable behavior changes that case to `not applicable`.
3. Run the Pulse model review. Any `ERROR` blocks before deployment work.
4. Read one deployment-plan row for the hub, then read the website-branding model/plan/assets and Pulse resources.
5. Expand the Pulse page template. Any unresolved token is an error.
6. **[PENDING]** Check-plan construction remains blocked (`bloqueado`) until the exact applicability predicate in `cfg.GetPulseCheckPlan` is extracted from the snapshot. Confirmed behavior is that the hub scope is enabled instances on the same server and in the same country and that enabled HTTP policies participate. This brief does **not** assert a Cartesian product between every in-scope instance and every enabled policy.
7. Preview prints the hub, public URL, destination directory, collector path, scheduled-task name, interval, and endpoint count. Preview writes nothing.
8. Apply backs up the existing page, web config, logo and collector under `ConfigBackupRoot\Pulse\<timestamp>`. The original backup set does **not** include the website-branding assets. **[PENDING]** Whether the port should add backup coverage for those branding assets is an owner/design decision; this brief does not add it.
9. Apply verifies resource/branding content hashes and writes the live branding assets, page, web config, logo and collector atomically. The production write pattern is a temporary file in the destination directory followed by replacement of the live target; this atomic live-asset replacement is source behavior, not part of the unapproved A6 persistence proposal.
10. Apply grants modify rights on the page and collector directories to the scheduled-task identity.
11. Apply registers the scheduled task using the hub IIS identity and password.
12. Apply runs one collection immediately.

### Scheduled collection

1. Read the check plan produced from the exact `cfg.GetPulseCheckPlan` semantics; portable plan construction remains blocked by step 6 until that predicate is extracted.
2. Execute one HTTPS check for each planned row; the old engine accepts the HTTP check type only.
3. Classify the response using the configured HTTP policy and timeout.
4. Call `ops.RecordPulseRun`, which updates per-check state and consecutive-failure counters and records the run.
5. Read the current snapshot through `ops.GetPulseStatusSnapshot`, including stale-state handling.
6. Write the status JSON file consumed by the Pulse page.

The portable catalog does not carry `ops.PulseCheckState` or `ops.PulseRun`. `docs/migration/analysis-pulse.md` **[PROPOSED]** replacing those central-state behaviors with a resolved plan file, the previous status file for counters/state, an atomic status-file rewrite, and one text-log line per collection. That persistence/file-state design is not an approved owner decision in the evidence used here and must remain `[PROPOSED]` until approved.

## 3. Portable catalog tables and columns

The Pulse and branding rows below list the exact carried-schema column names at `main@53719d23657ae1254bf42af731174e0c71edf26d`. They are schema inventory, not proof that every column is read by the old engine.

| Portable table | Exact carried columns relevant to this brief |
|---|---|
| `cfg_PulseHttpPolicy` | `ApplicationCode`, `UrlTemplate`, `HttpMethod`, `HealthyStatusCodes`, `RespondingStatusCodes`, `TreatRespondingAsHealthy`, `FollowRedirects`, `TimeoutSeconds`, `RequiredForOverallOverride`, `SortOrder`, `IsEnabled`, `ModifiedAt` |
| `cfg_PulseProfile` | `HubInstanceCode`, `DisplayName`, `PageTitle`, `PageDescription`, `RelativeDirectory`, `PublicUrlTemplate`, `StatusFileName`, `CollectorScriptPath`, `ScheduledTaskName`, `CollectionIntervalMinutes`, `RefreshSeconds`, `YellowFailureCount`, `RedFailureCount`, `StaleAfterSeconds`, `ScopePolicy`, `IsEnabled`, `ModifiedAt` |
| `cfg_PulseResource` | `ResourceCode`, `ResourceType`, `ResourceFileName`, `TextContent`, `BinaryContent`, `ContentSha256`, `IsEnabled`, `SortOrder`, `ModifiedAt` |
| `cfg_WebsiteBrandingProfile` | `ProfileCode`, `DocumentTitleTemplate`, `PulseDocumentTitleTemplate`, `ThemeColor`, `IsEnabled`, `ModifiedAt` |
| `cfg_WebsiteBrandingAsset` | `AssetCode`, `FileName`, `MimeType`, `BinaryContent`, `ContentSha256`, `IsRequired`, `SortOrder`, `IsEnabled`, `ModifiedAt` |

Additional carried tables used by the source analysis/model review are referenced only by columns verified to exist; this brief does not claim a complete column inventory for them:

| Portable table | Confirmed columns referenced here | Evidence limit |
|---|---|---|
| `cfg_Application` | `ApplicationCode`, `IsEnabled` | sufficient for `PULSE_HTTP_APPLICATION_MISSING`; exact check-plan applicability columns/predicate are **not confirmed**, see A2 |
| `dbo_ManagedServer` | `ServerCode`, `MachineName`, `ServicesRoot`, `ConfigBackupRoot`, `IsEnabled` | exact deployment-plan projection/order is not independently extracted here |
| `dbo_ManagedInstance` | `InstanceCode`, `ServerCode`, `CountryCode`, `CustomerCode`, `CustomerName`, `HostName`, `IisIdentityUserName`, `IsEnabled` | secret password is intentionally outside the portable catalog |

The original SQL review uses schema-qualified central objects such as `cfg.PulseProfile`, `cfg.PulseHttpPolicy`, `cfg.PulseResource` and `cfg.ManagedInstanceRuntime`. The portable SQLite catalog uses the carried table names above. The original `cfg.ManagedInstanceRuntime.IisIdentityPassword` is not a portable credential source; the port uses external credential input for the secret.

`ops.PulseCheckState` and `ops.PulseRun` are old central runtime state and are not carried into the portable catalog.

## 4. Credential input

The engine needs the hub instance IIS identity:

- catalog metadata: `IisIdentityUserName` of the hub instance;
- secret input: `IIS_IDENTITY.<HubInstanceCode>` from the credential package.

For the original `PULSE_TASK_CREDENTIAL_MISSING` predicate, the portable equivalent must preserve the intent: username must be non-empty and the matching credential must be present/decryptable to a non-empty secret. The password is never stored in the portable catalog and must never appear in logs, result rows, plan/status files or backups.

## 5. Network access

The old and approved portable behavior performs HTTPS health requests to application endpoints in the hub scope. The current source analysis describes policy data using the carried columns:

- method `GET`;
- `HealthyStatusCodes = 200-399`;
- `RespondingStatusCodes = 401,403`;
- `TreatRespondingAsHealthy = 1`;
- `FollowRedirects = 1`;
- `TimeoutSeconds = 12`.

The exact instance/application pair set is **not confirmed** until A2 is resolved; the values above describe policy semantics, not a cross-product rule.

The 2026-10-07 owner decision requires bounded parallelism with an overall deadline shorter than the collection interval, certificate validation by default, and any certificate-validation exception to be an explicit catalog setting. The current carried `cfg_PulseHttpPolicy` columns do not expose such a certificate-policy field; see ambiguity A3. No implementation may silently disable certificate validation.

## 6. Original Pulse model issue codes and exact severities

The exact `cfg.ReviewPulseModel` source defines these six codes. All are `ERROR`.

| Code | Severity | Exact source predicate to preserve |
|---|---|---|
| `PULSE_HUB_NOT_FOUND` | `ERROR` | No enabled `cfg.PulseProfile` for the requested hub joined to an enabled hub instance and enabled managed server. Portable mapping uses the corresponding carried instance/server tables. |
| `PULSE_TASK_CREDENTIAL_MISSING` | `ERROR` | A Pulse profile exists for the hub and either the hub IIS identity username or password is empty. Portable mapping keeps the username predicate and replaces the password column with external `IIS_IDENTITY.<HubInstanceCode>` credential presence/decryption. |
| `PULSE_RESOURCE_HASH_MISMATCH` | `ERROR` | For an enabled `cfg.PulseResource`, `ContentSha256` differs from lowercase SHA-256 of `TextContent` encoded as UTF-16LE bytes when text is non-null, otherwise `BinaryContent`. `docs/migration/catalog-conversion-plan.md` records that the stored resource hashes use the UTF-16LE representation. |
| `PULSE_HTTP_APPLICATION_MISSING` | `ERROR` | An enabled `cfg.PulseHttpPolicy` has no enabled `cfg.Application` with the same `ApplicationCode`. |
| `PULSE_PAGE_TEMPLATE_MISSING` | `ERROR` | No enabled `cfg.PulseResource` with `ResourceCode = 'PULSE_INDEX_HTML'`. |
| `PULSE_LOGO_MISSING` | `ERROR` | No enabled `cfg.PulseResource` with `ResourceCode = 'PULSE_LOGO'`. |

The old deployment also runs the website-branding review. Existing port-gap evidence identifies five original branding issue codes, all `ERROR`:

- `WEBSITE_BRANDING_PROFILE_MISSING`;
- `WEBSITE_BRANDING_REFERENCE_MISSING`;
- `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING`;
- `WEBSITE_BRANDING_ASSET_EMPTY`;
- `WEBSITE_BRANDING_ASSET_HASH_MISMATCH`.

The carried branding **column names are confirmed in section 3**, but this brief did not independently extract the exact stored-procedure predicate for those five issue codes. Their predicates must not be inferred from the names; see ambiguity A1.

## 7. Port invariants from preflight rules 6 and 7

### Rule 6: full active-machine comparison set

Pulse itself has a hub target rather than the `DEPLOYMENT_PREFLIGHT` per-instance selector, but the invariant still applies to every predicate or plan calculation that compares instances:

1. Build the comparison universe from **all enabled instances of the local machine**.
2. Apply the Pulse-specific same-country scope only after the local-machine enabled set is known.
3. Never make a duplicate/conflict/model predicate accidentally depend only on the selected/reporting target.
4. If a future API selects one hub/instance for reporting, compare against the full active-machine universe first and project the resulting finding to the selected target.

This invariant does not authorize inventing the missing `cfg.GetPulseCheckPlan` application-applicability predicate. Rule 6 defines the instance comparison universe; A2 still blocks the final check-plan rows.

### Rule 7: resolve and confine catalog-derived paths

No filesystem existence/read/write probe is allowed before containment is proved on the resolved path. Existing path segments must resolve symlinks, junctions and other reparse points.

At minimum E1 must apply this rule to:

- `ServicesRoot` and `ServicesRoot\HostName`: the resolved instance root must remain under the resolved services root;
- the Pulse page destination from `RelativeDirectory`: the resolved page directory must remain under the approved hub instance/site root;
- `CollectorScriptPath`: resolve before probe/write and confine it to its approved root once ambiguity A4 is answered;
- destinations derived from `ResourceFileName` and website-branding `FileName`: resolve before probe/write and confine them to the exact page/site root defined by the source plan;
- backup destinations below `ConfigBackupRoot`: resolve the root and reject any escaped destination;
- any plan/status destination derived from `StatusFileName` or other catalog text.

A lexical `GetFullPath` prefix test alone is insufficient.

## 8. Approved owner decisions E1 must respect

From the owner decisions already recorded:

- no Pulse profile on the machine means `not applicable`, not a deployment failure;
- scope remains same server plus same country;
- collector runs with the portable `pwsh.exe` at its current package path and apply re-registers the task;
- V1 scheduled-task identity remains the hub IIS identity;
- bounded parallelism is required; an example bound of 16 was accepted, with an overall deadline shorter than the interval;
- HTTPS certificate validation is on by default; exception requires explicit catalog configuration;
- use scheduler COM if the `ScheduledTasks` module is unavailable in PowerShell 7;
- website-branding assets remain owned by `PULSE_STATUS`, not `MANAGED_ASSETS`.

These are constraints for E1, not permission to invent missing schema, persistence decisions or source predicates. In particular, the plan/status-file persistence design in section 2 remains `[PROPOSED]`.

## 9. Ambiguities that block implementation details

### A1. Website-branding review predicates

Known: the exact carried branding columns in section 3, the five branding issue codes above and their `ERROR` severity.

Unknown in this brief: the exact original SQL predicate for each branding issue code.

**Question / required evidence:** extract the exact original website-branding review procedure from the snapshot before implementing any of the five checks. Until then, no per-code trigger is defined here.

### A2. Application applicability in the old Pulse check plan

Known: local enabled-instance universe, same-server/same-country hub scope, enabled HTTP policy data, and `ApplicationCode`/`IsEnabled` in `cfg_Application`.

Unknown: the exact application-applicability predicate in `cfg.GetPulseCheckPlan` that determines which instance/application pairs become checks.

**Blocking rule:** the plan-builder step is blocked until that predicate is extracted. Do not implement a full Cartesian product and do not substitute a plausible applicability flag.

### A3. Certificate-validation exception

The owner approved an explicit catalog setting for a certificate-validation exception. The current carried `cfg_PulseHttpPolicy` schema has no certificate-validation column.

**Question for the owner/schema task:** which catalog field represents this exception? E1 must validate certificates by default and must not invent or silently add a field in the engine PR.

### A4. `CollectorScriptPath` grammar and approved root

`CollectorScriptPath` is confirmed in `cfg_PulseProfile`, but rule 7 requires a precise approved root and path grammar before the engine can safely resolve/write it.

**Question / required evidence:** is the stored value absolute, template-based or relative, and which root does the old deployment plan authorize? Extract this from the original deployment-plan procedure before implementing the write.

### A5. Branding destination mapping

`cfg_WebsiteBrandingProfile` and `cfg_WebsiteBrandingAsset` columns are confirmed, but this brief did not independently extract the original plan rule that maps each branding `FileName` to a destination under the hub website root.

**Question / required evidence:** extract the exact branding-plan destination rule before implementing branding filesystem writes or containment tests.

### A6. Proposed portable state persistence

`docs/migration/analysis-pulse.md` proposes a resolved plan file, previous status file, atomic rewrite and text-log replacement for central runtime state. The evidence used by this brief does not contain an owner approval of that persistence design.

**Owner question:** approve, reject or amend that proposed state/persistence design before E1 treats it as settled behavior.

### A7. Checks cut off by the overall collection deadline

**[PENDING]** The owner decision fixes bounded parallelism and an overall deadline shorter than the collection interval, but it does not define the result semantics for checks that are still queued or are cancelled when that deadline expires. Before E1 implements the collector, decide whether those checks retain prior state, become a failure/unknown/not-run state, or are omitted, and define how that choice affects consecutive-failure counters, stale handling, the status snapshot and page counters. Collector behavior is blocked on this point; the deadline itself remains an approved constraint.

## 10. Test list by original issue code

Each implemented original issue code gets its own behavior test. The trigger must be the exact source predicate, not a reconstruction from the name.

| Code | Required test |
|---|---|
| `PULSE_HUB_NOT_FOUND` | Catalog with no enabled hub/profile/server join satisfying the exact predicate; expect exactly this `ERROR` for the hub. Include a valid control case. |
| `PULSE_TASK_CREDENTIAL_MISSING` | Two cases preserving the original OR predicate: empty catalog username, and valid username with missing/empty external IIS credential. Expect this `ERROR`; marker secret must not appear anywhere. |
| `PULSE_RESOURCE_HASH_MISMATCH` | Enabled text resource and enabled binary resource whose stored SHA-256 is changed independently of content; expect this `ERROR` for the resource. Valid hashes must not trigger. For the valid text control, use a non-ASCII, multiline value and calculate the expected SHA-256 independently from its UTF-16LE bytes; the test must not derive the expected value through the implementation path being tested. |
| `PULSE_HTTP_APPLICATION_MISSING` | Enabled HTTP policy whose `ApplicationCode` has no enabled matching application; expect this `ERROR`. Disabled policy is the negative control. |
| `PULSE_PAGE_TEMPLATE_MISSING` | Remove/disable only `PULSE_INDEX_HTML`; expect this `ERROR`. |
| `PULSE_LOGO_MISSING` | Remove/disable only `PULSE_LOGO`; expect this `ERROR`. |
| `WEBSITE_BRANDING_PROFILE_MISSING` | **Blocked by A1:** write the test only after the exact original predicate is extracted. |
| `WEBSITE_BRANDING_REFERENCE_MISSING` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_ASSET_EMPTY` | **Blocked by A1:** exact source predicate required. |
| `WEBSITE_BRANDING_ASSET_HASH_MISMATCH` | **Blocked by A1:** exact source predicate required. |

Additional integration/security tests after the blocking source questions are answered:

- full enabled-machine instance set is used before Pulse same-country projection (rule 6);
- check-plan tests use the exact A2 applicability predicate, including an instance/application pair that must be excluded;
- instance root junction escaping `ServicesRoot` is rejected before any probe;
- page/resource/branding/collector path junction or symlink escaping its approved root is rejected before any probe/write;
- a contained reparse target remains accepted;
- preview writes nothing;
- live branding/page/web-config/logo/collector writes use a temporary file and atomic replacement of the live target;
- unconditional live-target recovery for the original safeguarded set: inject a failure on the later collector write after page, web config and logo have already been replaced; require the step-8 backups to restore page, web config, logo and collector to byte-for-byte equality with their pre-apply state, regardless of which of those targets had already been replaced. Website-branding assets are intentionally excluded from this recovery assertion because the original step 8 does not back them up; adding such backup coverage remains the `[PENDING]` decision recorded above;
- **[PENDING A7]** deadline-cutoff coverage: create enough slow checks that some are queued or cancelled when the overall deadline expires, then assert the decided status/counter/stale/page-snapshot semantics. Do not freeze an expected outcome until A7 is decided;
- HTTPS certificate validation is enabled by default;
- healthy, responding-as-healthy, redirect, timeout/refused and failed responses preserve `HealthyStatusCodes`/`RespondingStatusCodes` semantics;
- scheduled-task COM fallback is covered when `ScheduledTasks` is unavailable;
- marker IIS credential is absent from result, logs and generated artifacts;
- machine without a Pulse profile returns `not applicable`.

If the A6 persistence proposal is approved, add proposal-specific tests for atomic plan/status writes, state continuation, threshold transitions at 1 and 3 consecutive failures, stale handling and restorable backup behavior. Those tests are not evidence that A6 is already approved.

## 11. E1 entry gate

E1 can implement the six exact Pulse-model predicates and non-ambiguous orchestration behavior only after its PR re-reads the exact source snapshot. Before coding website-branding checks, the check plan, collector destination, certificate exception, branding destination, portable state persistence or deadline-cutoff result semantics, resolve A1-A7 with source/owner evidence. If an exact predicate remains unclear, stop on that item and name the ambiguity; do not infer it from an issue code or current document wording.
