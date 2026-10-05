# Register of open decisions and doubts (documentation tasks of 2026-10-05)

**Status:** [PROPOSED] consolidation for the reviewer and the owner. It lists every [PENDING] of the documents produced in the documentation tasks (PRs #27 to #35, #39, #41 to #44) with the recommendation made there. **None of these is an owner decision**; the last column is for the owner's answer. The sources are documents on open PRs; this register changes none of them.
**Date:** 2026-10-05
**How to use:** answer in the last column (accept, reject or change); the reviewer then records accepted decisions in `docs/decisions-log.md` and moves the document edits into the source PRs.

## S. Scope and architecture

| ID | Question | Recommendation | Source | Needed | Owner decision |
|---|---|---|---|---|---|
| S1 | Order of `FULL_DEPLOYMENT` on a clean server: the shared account is created after IIS; the Keycloak database is populated after `DATABASE_SETTINGS`; client secrets run before the service first starts; the Keycloak files must exist | Reorder or split into phases and prove it on the pilot (a clean server) | #41 #34 #35 #39 | before the pilot | [ ] |
| S2 | Software and Keycloak-file update path: 30 of 51 clone plans were updates from a package and nothing in the 19 engines does it | Decide before wave 5 is ported; treat it as a feature outside the 19 engines | #28 #35 #41 | before wave 5 port | [ ] |
| S3 | Scope of the six old-console features that are not engines (environment clone, file copy, archive restore, housekeeping, environment power, version inventory) | A separate phase after wave 9, in this order: file copy and update deployment, archive restore, power, clone, version inventory, housekeeping | #28 | before planning phase 6b | [ ] |
| S4 | Where a plan lives between preview and apply (no database) | A signed text file in the log folder with fingerprint and expiry, revalidated at apply | #28 #41 | before the first mutating engine | [ ] |
| S5 | Composite run when one instance fails: stop everything or only that instance | Stop that instance, continue the others, fail at the end with counts | #41 | before `FULL_DEPLOYMENT` port | [ ] |
| S6 | Require a successful preview (by fingerprint) before apply (the history shows none was ever run) | Yes | #41 | before `FULL_DEPLOYMENT` port | [ ] |
| S7 | Preflight phase read-only; software installation as the first execution step with a real preview | Yes | #41 #35 | before `FULL_DEPLOYMENT` port | [ ] |
| S8 | Retire `V8_KEYCLOAK_CONFIG` (covered by the `CONFIG_REPAIR` rule `KEYCLOAK_DB_URL`) and remove its action, engine row and disabled step 63 | Yes, after the owner confirms | #43 | before wave 8 | [ ] |
| S9 | `LINKS_VISIBILITY` writes configuration: option A (effective matrix plus a change proposal applied by the owner and sealed), B (override file) or C (edit the catalog by hand); and is it needed in V1 (1 of 70 instances has an override) | Option A, read-only matrix first | #43 | before wave 8 | [ ] |
| S10 | Retire the legacy `DATABASE_SETTINGS` engine and `cfg.DatabaseSettingRule` (all 14 codes are in the newer table) | Yes | #39 | before wave 5 | [ ] |
| S11 | `DATABASE_COPY` allowed source and destination pairs (copying overwrites the destination and moves customer data) | An allowlist of pairs or a "may be overwritten" flag on the destination, checked in the plan | #44 | before wave 9 and before any real use | [ ] |
| S12 | `DATABASE_COPY`: archive creation and restore to move databases to another machine | In scope | #44 #28 | wave 9 | [ ] |
| S13 | `DATABASE_COPY`: retention and cleanup of source and safety backups | Retention in the policy; never delete the newest safety backup of a destination | #44 | wave 9 | [ ] |
| S14 | `DATABASE_COPY`: post-copy settings sync mandatory; destination Keycloak database after a copy | Mandatory unless explicitly skipped and logged; decide the Keycloak case with its design | #44 | wave 9 | [ ] |

## K. Security and credentials

| ID | Question | Recommendation | Source | Needed | Owner decision |
|---|---|---|---|---|---|
| K1 | Issuer private key: storage, backup, custody and compromise procedure (R-045) | Encrypted in the vault backups, a named second custodian, a rehearsed re-pin of the six machines | #30 #33 | before the credential tool is used | [ ] |
| K2 | Vault passphrase: second custodian or sealed offline copy (R-046) | Yes | #30 #33 | before the old database is retired | [ ] |
| K3 | Rollback of an older, validly signed folder is not prevented by the manifest | A monotonic counter in the manifest checked against the last run on the machine (a contract change) | #33 | before Phase 3 | [ ] |
| K4 | Install location and ACL of the portable folder; re-verification before each module load | A protected folder; verify again before loading | #33 | before Phase 3 | [ ] |
| K5 | Do release builds omit the development flag that skips verification | Yes | #33 | before release | [ ] |
| K6 | Session design: token transport, expiry, binding | Design in Phase 1C before any mutating route | #33 | Phase 1C | [ ] |
| K7 | Tamper-evident logs; secrets in memory and crash dumps | A hash chain per day (low priority); disable dumps for the process | #33 | later | [ ] |
| K8 | Identity and rights of tasks and services created by engines (Pulse task, Windows services) | Review per engine | #33 #31 #35 | per engine port | [ ] |
| K9 | Connection encryption and certificate trust for SQL connections (tools and engines) | Encrypt and validate by default, with an explicit exception setting | #39 #35 | before engine ports that use SQL | [ ] |
| K10 | TLS validation of outbound HTTP checks (Pulse, probe, Keycloak endpoint) | Validate by default; an exception is an explicit catalog setting | #31 #35 #42 | per engine port | [ ] |
| K11 | Engine backup folders hold old files with secrets: ACL and retention | Administrators only; keep the last 10 runs; never delete the latest per file | #32 #39 #44 | per engine port | [ ] |
| K12 | One secret value per rule for all instances (`RULE_SECRET`) | Keep; review per-instance secrets before customer-facing rollouts | #32 #35 | wave 4 | [ ] |
| K13 | Passwords of local accounts reset on every apply (Web Access, services) | Reset only when the credential changed | #35 #39 | per engine port | [ ] |

## C. Catalog, conversion and contracts

| ID | Question | Recommendation | Source | Needed | Owner decision |
|---|---|---|---|---|---|
| C1 | Instance directory: include `LinksAssignedUserName` (printed on the public page; may be a person's name) | Include it, since the page already shows it | #29 | before the directory is built | [ ] |
| C2 | A catalog of a machine without a general page carries no directory | Yes | #29 | before the directory is built | [ ] |
| C3 | How a change of an instance on one machine reaches the other catalogs | Reconvert all machines and reseal; no partial hand edit of the directory | #29 #30 | before cutover | [ ] |
| C4 | The old published-links manager (`ui.PublishedEnvironmentLink`) is outside V1 | Yes; the pages written by `LINKS_PAGES` replace it | #29 | before wave 5 | [ ] |
| C5 | Stale catalog: change freeze and refresh cadence while both systems run (R-044) | Reconvert and reseal before every cutover; freeze changes meanwhile | #30 | before cutover | [ ] |
| C6 | Who may edit a catalog and whether a second reader is required (R-047) | Keep the baseline and the seal log; a second reader for production catalogs | #30 #33 #43 | before the first edit | [ ] |
| C7 | Convert the 61 database content filters to structured predicates (conversion tool and catalog contract) | Yes, before `DATABASE_CONTENT_SYNC` is ported | #39 | before wave 5 port | [ ] |
| C8 | Add the action-code cross-reference check to `Test-CatalogConversion` (R-043) | Yes (a tool change, separate PR) | #30 | before wave 5 | [ ] |
| C9 | A catalog-change function in the tools (for `LINKS_VISIBILITY` proposals and owner edits) | A separate PR after option A is chosen | #43 | wave 8 | [ ] |
| C10 | How the 25 SQL client files reach the portable build; x86 and arm64 operator machines | A verified CI artifact; state the platform limit | #30 #33 | before the portable build | [ ] |
| C11 | Prerequisite model for installers (name, source file, SHA-256, target, version check) in the catalog; installer folder; JDK 23 is a short-term release | Yes; an operator-given folder pinned by hash; confirm the Keycloak requirement first | #35 | before wave 4 port | [ ] |

## E. Engine specifications

| ID | Question | Recommendation | Source | Needed | Owner decision |
|---|---|---|---|---|---|
| E1 | `DEPLOYMENT_PREFLIGHT`: a missing credential package is an error for the services check; `FULL_DEPLOYMENT` does not stop on warnings; port all 12 reviews (4 code sets still to extract); show the catalog date as information | Error; no stop on warnings; all 12; information row | #31 | wave 1 port | [ ] |
| E2 | `PULSE_STATUS`: bounded parallel checks with an overall deadline; scheduler interface if `ScheduledTasks` does not load under PowerShell 7; keep branding assets in this engine | Parallel (for example 16); COM interface if needed; keep | #31 | wave 1 port | [ ] |
| E3 | `CONFIG_REPAIR`: behaviour of a selector with no match or several matches; restarts after a repair stay out; keep the bounded retry for just-written files | Derive the old behaviour with a differential test; out of scope; keep | #32 | wave 2 port | [ ] |
| E4 | `MANAGED_ASSETS`: 14 enabled instances without a logo (PRESALES 8, TENDERS 6): error as today or warning; validate PNG and size; inherited ACLs; never delete | Warning and no write; yes; keep; never | #32 | wave 2 port | [ ] |
| E5 | `IIS_RECONCILE`: **certificate store** (the ADR-0006 condition says `MY`, all four policies use `WebHosting`) | Treat the store as policy data, compare only the case, test `WebHosting` on the runner, reword the condition | #34 | wave 3 port | [ ] |
| E6 | `IIS_RECONCILE`: V1 never deletes unmanaged objects; IIS-29 out of scope; mechanism for Windows features (IIS-01); IIS-20 policy; swallowed errors as warnings; backup mechanism | Never delete; out; decide after T-01; report and require approval; yes; decide | #34 | wave 3 port | [ ] |
| E7 | Shared pool and service account: where it is created and who owns it (ties to the order decision) | Ensure it in a step before IIS | #34 #35 | before the pilot | [ ] |
| E8 | `WINDOWS_SERVICES`: restart only services that changed; the logon-right helper under PowerShell 7; passwords on a shared account | Only changed; a small native call, tested; one credential per machine for that account | #35 | wave 4 port | [ ] |
| E9 | `V8_KEYCLOAK_PREREQUISITES`: system-directory library alternative | Test whether the JDBC driver finds it next to the Keycloak files | #35 | wave 4 port | [ ] |
| E10 | `V8_KEYCLOAK_SERVICE`: who puts the Keycloak files on the instance; service log rotation | With the update path decision; size-based rotation | #35 | wave 4 port | [ ] |
| E11 | `KEYCLOAK_CLIENT_SECRETS` and `DATABASE_CONTENT_SYNC`: Keycloak data through its database or its admin interface; effect on a running Keycloak; skip missing databases with a warning and rerun after the service steps | Test [V]; skip with a warning and rerun | #35 #39 | wave 4 and 5 port | [ ] |
| E12 | `WEB_ACCESS`: restart the root pool only when something changed; keep machine-scope protection for the credential file | Only on change; keep | #39 | wave 5 port | [ ] |
| E13 | `LINKS_PAGES`: remove the generation time from the compared content; "policy missing" for PRESALES and TENDERS on the pilot | Remove it; confirm it is intended | #39 | wave 5 port | [ ] |
| E14 | `FULL_DEPLOYMENT`: a "resume from step" option | Optional, after idempotency is proven | #41 | later | [ ] |
| E15 | `ENVIRONMENT_STATE_PROBE`: persist the state; probe by public name or loopback; one shared HTTP classifier with Pulse | A status file and a log line, no database; public name by default; share the module | #42 | wave 7 port | [ ] |
| E16 | `STORAGE_SIZE_SCAN`: where measurements are kept; time budget; gigabyte unit | JSON-lines history in the log folder; 300 s with an explicit full-scan option; binary | #42 | wave 7 port | [ ] |
| E17 | `MODEL_REVIEW`: separate action or the preview of the preflight; show catalog status | A read-only screen on the shared reviews; yes | #42 | wave 7 port | [ ] |

## V. Validations needing a real server [V]

| ID | What | Source |
|---|---|---|
| V1 | SQL Server LocalDB limits on the runner (backup compression, several instances) for the `DATABASE_COPY` tests | #44 |
| V2 | TSplus and Web Access backend, real pool restart under load | #39 |
| V3 | Hundreds of pools: batched IIS commits, backup size and time, locked sections, real pool identities, central certificate store | #34, ADR-0006 conditions 2 to 4 |
| V4 | Real Keycloak: client data and secrets through the database, caches, start time and log growth | #35 #39 |
| V5 | Real SQL instances: sizes, time, service-account folder rights, antivirus on backups, disk space | #44 |
| V6 | Probing the public host name from the server itself: DNS, hairpin, firewall; timing at 21 instances | #42 #31 |
| V7 | Real roots of hundreds of gigabytes for the storage scan | #42 |
| V8 | Live `_sisqualMANAGEMENT`: counts, orphans, collation, certificate trust, one-time credential import | plan, #30 |
| V9 | The pilot (a clean server) and a sandbox: a full run with a preview first | #41 |
| V10 | A real service and connector restart effect on the mobile app | #35 |

**Count:** 55 decisions (S 14, K 13, C 11, E 17) and 10 validations. Some rows group several small [PENDING] points of one document; the source documents list them one by one.

## Already decided by the owner (not repeated above)

For traceability, decided on 2026-10-05 and recorded in the plan, the contract notes and the handoff note: ADR-0007 accepted; the two process rules (stacked PRs, traceable decisions); all PowerShell on PowerShell 7; the 5 `SANDBOX_*_HUB` links obsolete; credential answers Q1 to Q10 (Q3 text package pasted into the application; no rotation of the 16 exposed secrets); the four answers on the Pulse analysis (scope kept and renamed by a manual edit, collector from the portable `pwsh.exe`, task as the hub identity, "not applicable" without a hub). Two readings are still to confirm: "A" to Q2 as also approving the canonical form, and "A" to Q10 as "yes".
