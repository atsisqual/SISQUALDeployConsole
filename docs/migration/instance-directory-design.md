# Design: the instance directory for the general links page

**Status:** [CONFIRMED] C1/C2 contract implemented in PR #57. The source analysis remains the design basis; exact real-snapshot counts remain evidence, not a runtime invariant.
**Date:** 2026-10-05; implementation update 2026-10-06.
**Sources (read only):** `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (29,516,382 bytes, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the `LINKS_PAGES` engine exported from `ops.Engine` (`Invoke-LinksPageDeployment.ps1`). Script text is not copied; objects are cited by name.
Tags: [CONFIRMED] source or owner decision; [IMPLEMENTED] portable tooling; [PENDING] later work; [V] real-server validation.

## 1. Summary

1. [CONFIRMED] Only a page with `LinksIncludeAllInstances = 1` (a "general" page) lists instances of other machines: it lists every enabled instance of the same country on every enabled machine (`cfg.GetLinksPageItemPlan`). An individual page lists only its own instance.
2. [CONFIRMED] In the 2026-10-05 reference snapshot all six machines have such a page, so all six catalogs need directory rows. Over those six catalogs the directory has 36 rows (largest: PRESALES with 17), about 1.4 KB of text at most per catalog.
3. [CONFIRMED, C1] The directory is `cfg_LinksPageDirectory` with seven public columns, including `AssignedUserName` from `LinksAssignedUserName`. The owner accepted C1 in Q9 on 2026-10-06 because the current public page already displays it.
4. [CONFIRMED, C2] Every catalog has the derived table. A machine without an enabled general page gets an empty table, so no remote instance data is carried for that machine. This is the implemented representation of the owner C2 decision.
5. [CONFIRMED] No secret, token, SQL configuration, port or path data travels in the directory.
6. [CONFIRMED] `LinksHubInstanceCode` is not a cross-machine directory reference. It limits an application to the page of its own hub instance, so other catalogs need nothing about that instance.
7. [IMPLEMENTED] `Convert-ManagementDb.ps1` derives the table during the cut; `Test-CatalogConversion.ps1` recomputes it independently and validates it.

## 2. What the general page needs

`cfg.GetLinksPageItemPlan` takes the page instance and returns one row per target instance and published application:

- Target instances: if the page instance has `LinksIncludeAllInstances = 1`, every enabled instance of an enabled server whose `CountryCode` equals the page instance's, on any machine; otherwise only the page instance.
- Applications: every enabled `cfg.Application` with `PublishInLinks = 1` (12 of 36 in the reference snapshot), crossed with the targets. The URL is the application's `LinksUrlTemplate` expanded by `cfg.ExpandTemplate`, or `https://` + host name + the application's `IisPath`.
- Visibility layers (instance override in `cfg.LinksPageInstanceApplication`, then profile in `cfg.LinksProfileInstance` and `cfg.LinksProfileApplication`, then the application's default) apply only to individual pages. On a general page all published applications show for every target.
- Order: country, customer code (NULL last), customer code, instance code, application sort order.

[CONFIRMED] The six general pages in the reference snapshot are: DEMOBR (BR_DEMO, BR), DEMOES (ES_DEMO, ES), DEMOPT (PT_DEMO, PT), PRESALESMAIN (PRESALES, PT), SANDBOXMAIN (SANDBOX_HUB, US), TENDERMAIN (TENDERS, US). Two machines build a Portuguese page and two build a US page, each listing all enabled instances of that country.

## 3. Exact columns

| Directory column | Source column of `dbo.ManagedInstance` | Used for | Nullability |
|---|---|---|---|
| `InstanceCode` | `InstanceCode` | key, ordering, QR asset lookup | NOT NULL, primary key |
| `ServerCode` | `ServerCode` | provenance and verifier checks | NOT NULL |
| `CountryCode` | `CountryCode` | selection and grouping | NOT NULL, two characters |
| `CustomerCode` | `CustomerCode` | ordering and QR asset (`QR_CHANNEL_<code>` in global `cfg.LinksPageAsset`) | NULL allowed |
| `CustomerName` | `CustomerName` | card title; page falls back to instance code | NULL allowed |
| `HostName` | `HostName` | link construction | NOT NULL, non-empty |
| `AssignedUserName` | `LinksAssignedUserName` | displayed on the public card | NULL allowed; C1 accepted |

[CONFIRMED] The real source schema permits NULL for `CustomerCode` and `CustomerName`, and the existing page logic already handles those cases. The earlier draft that marked both columns NOT NULL was too strict; PR #57 preserves the source NULLs rather than inventing values.

[CONFIRMED] No link or page template mentions `MOBILE_APP_TOKEN`, and the engine never reads a token. The directory also excludes `SqlInstanceName`, `DatabaseName`, `ChannelID`, Keycloak ports, credentials and path configuration.

Only enabled instances of enabled machines are selected, so no `IsEnabled` column is needed.

## 4. Which catalogs carry rows, and how many

Rule [CONFIRMED]: the directory of catalog M contains enabled instances of enabled **other** machines whose country equals the country of at least one enabled general-page instance of M. A row is present once even if more than one local page needs it. The table is empty when M has no enabled general page or when M itself is disabled.

Reference snapshot evidence:

| Catalog | Countries of its general pages | Local instances in the page | Directory rows | Coming from |
|---|---|---:|---:|---|
| BR_DEMO | BR | 21 | 1 | SANDBOX_HUB |
| ES_DEMO | ES | 16 | 1 | SANDBOX_HUB |
| PT_DEMO | PT | 16 | 9 | PRESALES (8), SANDBOX_HUB (1) |
| PRESALES | PT | 8 | 17 | PT_DEMO (16), SANDBOX_HUB (1) |
| SANDBOX_HUB | US | 2 | 6 | TENDERS |
| TENDERS | US | 6 | 2 | SANDBOX_HUB |
| **Total** | | | **36** | |

The three MX instances on ES_DEMO and other-country sandbox instances have no matching general page and therefore do not become remote directory rows. A new-machine catalog has no local general page and receives an empty directory until such a page exists.

The 36-row reference count is a snapshot regression target, not a hard-coded product rule. [V] Re-run the real-snapshot reconciliation before cutover.

## 5. Table design [IMPLEMENTED]

`cfg_LinksPageDirectory` is a derived `STRICT` table with no foreign key to `dbo_ManagedInstance`, because its rows are by definition remote. Its schema is built from the real `dbo.ManagedInstance` source column metadata, with `AssignedUserName` mapped from `LinksAssignedUserName`.

The exact destination column order is:

1. `InstanceCode`
2. `ServerCode`
3. `CountryCode`
4. `CustomerCode`
5. `CustomerName`
6. `HostName`
7. `AssignedUserName`

Text is preserved byte for byte as in the source. `ServerCode` is never the catalog's own server. The table is empty, not absent, for a machine without an enabled general page.

C1/C2 does not change the source-carried catalog schema contract, so on its isolated branch it keeps `schema_version = 1` and bumps `cut_rule_version` to 2. The later C7 schema-v2 change is reconciled when the PRs are integrated.

## 6. Verification in the conversion [IMPLEMENTED]

1. The converter builds the directory from the complete source model and records `linksPageDirectoryCount` per catalog in `conversion-manifest.json`.
2. The verifier recomputes the expected rows independently from `dbo.ManagedServer` and `dbo.ManagedInstance`; it does not call the converter's directory-row function.
3. The verifier requires the exact seven-column public shape and exact row/value equality.
4. It requires no local `InstanceCode`, no row with the catalog's own `ServerCode`, and every directory country to be served by an enabled local general page.
5. For C2, a catalog without an enabled general page must have zero directory rows.
6. The converter's existing secret-like safety scan is applied to the derived directory before it is written; the catalog verifier's existing stored-byte secret checks remain in force.
7. A dedicated mutation test changes a directory `HostName` and proves that the independent verifier fails.
8. The existing 62 source-carried tables remain the source whitelist. The directory is derived and is not read as a 63rd SQL Server source table.

[CONFIRMED, PR #57 evidence] The dedicated synthetic unit suite exercises populated and empty directories, C1 `AssignedUserName`, NULL customer fields, disabled instance/server filtering, manifest counts and mutation detection. The common SQL Server/LocalDB integration proves file-source and SQL-source output remain value-identical.

## 7. Size and freshness

The reference snapshot contains about 36 directory rows in total, so the storage cost is negligible. The real concern is freshness: when a remote instance is renamed, moved or disabled, every catalog that carries it can become stale.

[CONFIRMED, owner C3, Q6 on 2026-10-06] Propagation is by reconverting all machines and resealing; there is no partial hand edit of the directory. The manifest exposes catalog build provenance for operator review before cutover.

## 8. `LinksHubInstanceCode`

[CONFIRMED] In `cfg.GetLinksPageItemPlan`, an application with a hub code appears only on the page of that hub instance and only for the hub instance itself. In the reference snapshot the only such application is `PULSE_STATUS` ("System Pulse", hub `DEMOPT`).

Consequences:
- keep `LinksHubInstanceCode` as a plain code in global `cfg_Application`, with no foreign key and no resolution through `cfg_LinksPageDirectory`;
- other catalogs need nothing about DEMOPT for this purpose;
- the directory is not involved in Pulse hub selection.

## 9. Decisions

1. **C1 - `LinksAssignedUserName`: [CONFIRMED] accepted Q9, 2026-10-06.** Include it as `AssignedUserName`; the public page already displays it.
2. **C2 - machine without a general page: [CONFIRMED] accepted Q9, 2026-10-06.** Carry no remote directory data; implementation keeps the derived table present but empty for a stable catalog shape.
3. **C3 - remote instance changes: [CONFIRMED] accepted Q6, 2026-10-06.** Reconvert all machines and reseal; no partial directory edit.
4. The old published-links manager (`ui.PublishedEnvironmentLink`, `ui.GetPublishedEnvironmentLinks`, `ui.GetPublishedLinksManager`) is outside the `LINKS_PAGES` engine. Its V1 retirement/replacement is tracked separately from C1/C2.
5. The old `cfg.SyncLinksPageInstanceApplications` central write is also outside C1/C2. The read-only portable `LINKS_PAGES` behavior is specified separately.

## 10. Follow-ups outside C1/C2

- [V] Reconcile the six real catalogs against the reference snapshot counts before cutover.
- Integrate this cut-rule change with C7/C8 after their isolated PRs are accepted; do not duplicate the derived table as a source-carried table.
- C9 covers catalog-change/reseal tooling for Links visibility and is not part of this PR.
- Runtime consumption belongs to the later `LINKS_PAGES` engine wave.
