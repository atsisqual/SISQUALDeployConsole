# Design: the instance directory for the general links page

**Status:** [PROPOSED] design for review. It settles the "[PENDING] exact columns and which catalogs carry it" of `docs/roadmap.md` section 5 and the decision of 2026-10-05 recorded in `docs/decisions-log.md` (a catalog that hosts a general links page carries a read-only directory of the instances of other machines). No product code and no change to the contracts in this PR.
**Date:** 2026-10-05
**Sources (read only):** `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (29,516,382 bytes, blob `9401e2c3cb2517ca88848f902ff4d3786583e888`, head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the `LINKS_PAGES` engine exported from `ops.Engine` (`Invoke-LinksPageDeployment.ps1`). Script text is not copied; objects are cited by name.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Summary

1. [CONFIRMED] Only a page with `LinksIncludeAllInstances` = 1 (a "general" page) lists instances of other machines: it lists every enabled instance of the same country on every enabled machine (`cfg.GetLinksPageItemPlan`). An individual page lists only its own instance.
2. [CONFIRMED] All six machines have such a page, so all six catalogs need a directory. Over the six catalogs the directory has **36 rows** (largest: PRESALES with 17), about 1.4 KB of text at most per catalog.
3. [PROPOSED] The directory is one table, `cfg_LinksPageDirectory`, with 6 columns, public data only. No secret, no token, no SQL, port or path data travels in it.
4. [CONFIRMED] `LinksHubInstanceCode` is not a cross-machine reference. It limits an application to the page of its own hub instance, so other catalogs need nothing about that instance (section 8). This also corrects a statement of `analysis-pulse.md` (PR #27).
5. [PROPOSED] The conversion tools build the directory, and `Test-CatalogConversion` checks it against the source (section 6). The directory is the only cross-machine data in a catalog.

## 2. What the general page needs

`cfg.GetLinksPageItemPlan` takes the page instance and returns one row per target instance and published application:

- Target instances: if the page instance has `LinksIncludeAllInstances` = 1, every enabled instance (of an enabled server) whose `CountryCode` equals the page instance's, on any machine; otherwise only the page instance.
- Applications: every enabled `cfg.Application` with `PublishInLinks` = 1 (12 of 36), crossed with the targets. The URL is the application's `LinksUrlTemplate` expanded by `cfg.ExpandTemplate`, or `https://` + host name + the application's `IisPath`.
- Visibility layers (instance override in `cfg.LinksPageInstanceApplication`, then profile in `cfg.LinksProfileInstance` and `cfg.LinksProfileApplication`, then the application's default) apply **only to individual pages**. On a general page all published applications show for every target.
- Order: country, customer code (null last), customer code, instance code, application sort order.

[CONFIRMED] The six general pages (instances with `LinksIncludeAllInstances` = 1): DEMOBR (BR_DEMO, BR), DEMOES (ES_DEMO, ES), DEMOPT (PT_DEMO, PT), PRESALESMAIN (PRESALES, PT), SANDBOXMAIN (SANDBOX_HUB, US), TENDERMAIN (TENDERS, US). Two machines build a Portuguese page and two build a US page, each listing all instances of the country.

## 3. Exact columns

| Plan column | Source column of `dbo.ManagedInstance` | Used for | In the directory |
|---|---|---|---|
| `TargetInstanceCode` | `InstanceCode` | key, ordering, QR asset lookup | yes |
| `TargetCountryCode` | `CountryCode` | selection and grouping of the page | yes |
| `TargetCustomerCode` | `CustomerCode` | ordering and the QR asset (`QR_CHANNEL_<code>` in `cfg.LinksPageAsset`, global) | yes |
| `TargetCustomerName` | `CustomerName` | card title (falls back to the instance code) | yes |
| `TargetHostName` | `HostName` | every link: all 12 `LinksUrlTemplate` values use only the host name placeholder, and the default URL uses the host name | yes |
| `TargetAssignedUserName` | `LinksAssignedUserName` | shown on the card (10 non-empty values, none with an at sign) | [PENDING] see section 9 |
| `TargetServerCode` | `ServerCode` | not used by the engine | yes, as provenance and for the checks |
| `TargetCultureCode` | `CultureCode` | not used by the engine | no |
| (not selected) | `SqlInstanceName`, `DatabaseName`, `ChannelID`, Keycloak ports, credentials, `MOBILE_APP_TOKEN` | other `ExpandTemplate` tokens | no, never |

[CONFIRMED] No link or page template mentions `MOBILE_APP_TOKEN`, and the engine never reads a token. The QR images are fixed assets keyed by customer code.

Only enabled instances of enabled machines are in the directory, so no `IsEnabled` column is needed.

## 4. Which catalogs carry it, and how many rows

Rule [PROPOSED]: the directory of the catalog of machine M holds the enabled instances of **other** machines whose country equals the country of a general-page instance of M. Rows are listed once even if two pages need them.

| Catalog | Countries of its general pages | Local instances in the page | Directory rows | Coming from |
|---|---|---:|---:|---|
| BR_DEMO | BR | 21 | 1 | SANDBOX_HUB |
| ES_DEMO | ES | 16 | 1 | SANDBOX_HUB |
| PT_DEMO | PT | 16 | 9 | PRESALES (8), SANDBOX_HUB (1) |
| PRESALES | PT | 8 | 17 | PT_DEMO (16), SANDBOX_HUB (1) |
| SANDBOX_HUB | US | 2 | 6 | TENDERS |
| TENDERS | US | 6 | 2 | SANDBOX_HUB |
| **Total** | | | **36** | |

The 3 MX instances on ES_DEMO and the other-country sandbox instances have no general page, so they appear only on their own individual pages. A catalog of a new machine (the pilot) has no instances and no general page unless the owner adds one; then the rule gives its directory.

## 5. Table design [PROPOSED]

Table `cfg_LinksPageDirectory`, `STRICT`, no foreign key to `dbo_ManagedInstance` (the rows are by definition not local).

| Column | Type | Rule |
|---|---|---|
| `InstanceCode` | TEXT, primary key | not in `dbo_ManagedInstance` of the same catalog |
| `ServerCode` | TEXT, not null | different from `catalog_meta.server_code` |
| `CountryCode` | TEXT, not null, 2 characters | equals the country of a general-page instance of this catalog |
| `CustomerCode` | INTEGER, not null | |
| `CustomerName` | TEXT, not null | |
| `HostName` | TEXT, not null | non-empty |
| `AssignedUserName` | TEXT, null | only if section 9 item 1 is accepted |

Text is byte for byte as in the source and compared exactly, like every other table. The table is empty, not absent, when the machine has no general page. [PROPOSED] bump `cut_rule_version`.

## 6. Verification in the conversion

[PROPOSED] additions to `Convert-ManagementDb` (cut and new-machine modes) and `Test-CatalogConversion`; the tools are not changed in this PR.

1. The converter builds the directory from the source with the rule of section 4 and reports the count per catalog in the manifest.
2. The verifier recomputes the expected set from the source independently and requires an exact match (rows and values), per catalog.
3. No row repeats a local instance; no row has the catalog's own `ServerCode`; every row's country belongs to a general page of the catalog; each general page instance exists in `dbo_ManagedInstance` of the catalog.
4. The only tables that carry an instance code of another machine are `cfg_LinksPageDirectory` and the global `cfg_Application.LinksHubInstanceCode`; a scan fails on any other.
5. The directory has no column outside section 5, and the secret scan covers it.
6. Counts equal the table of section 4 on the 2026-10-05 snapshot (a regression test on the real data, kept out of the repository).

## 7. Size and freshness

About 36 rows in total, at most 1.4 KB of text per catalog: negligible next to the 7 MB catalogs. The real cost is **freshness**: when an instance on one machine is renamed, moved or disabled, every catalog that carries it must change. [PROPOSED] the conversion run is repeated for all machines and the catalogs are sealed again; the manifest already shows the catalog's build time, and a preview of `LINKS_PAGES` lists the directory rows and the catalog date. This is registered as a risk in the risk register update (task 2).

## 8. `LinksHubInstanceCode`

[CONFIRMED] In `cfg.GetLinksPageItemPlan` an application with a hub code appears only on the page of that hub instance and only for the hub instance itself. The only such application is `PULSE_STATUS` ("System Pulse", hub `DEMOPT`); it appears on the DEMOPT page and nowhere else, even though 17 profile rows mention it.

Consequences:
- [PROPOSED] Keep it as a plain code in the global `cfg_Application`, with no foreign key and no resolution. The check is a string comparison with the page instance code when the plan is built.
- Other catalogs need nothing about DEMOPT. The directory is not involved.
- [PROPOSED] The finding that `Convert-ManagementDb` raises ("refers to an instance of another machine") is noise and can be dropped in a later tool change.
- Correction: `analysis-pulse.md` (PR #27) said that other machines' links pages show the Pulse card pointing to the PT hub. That was wrong; it is corrected there.

## 9. [PENDING] decisions

1. `LinksAssignedUserName` is printed on the public general page, so putting it in the directory adds no exposure, but it may be a person's name. Is it meant to be public? Recommendation: include it (the page already shows it) and say so.
2. Should a catalog of a machine without a general page still carry a directory? Recommendation: no, as in section 4.
3. How are other machines' instance changes propagated (section 7)? Recommendation: repeat the conversion for all machines and reseal; no partial editing of the directory by hand.
4. The old console also had a "published links manager" (`ui.PublishedEnvironmentLink`, 55 rows, procedures `ui.GetPublishedEnvironmentLinks` and `ui.GetPublishedLinksManager`) behind an anonymous catalogue route; it lists published instances of all machines, is not part of the `LINKS_PAGES` engine, and is not in the 19 engines. Recommendation: not in V1; the pages written by `LINKS_PAGES` replace it.
5. The engine also called `cfg.SyncLinksPageInstanceApplications`, which inserts default visibility rows for instances without a profile or override into the central table; the catalog is read-only. Recommendation: compute the default (the application's `LinksDefaultForIndividualPages`) in memory when the plan is built, without writing. To be written in the `LINKS_PAGES` spec.

## 10. Follow-ups outside this PR

- Update `contracts/catalog-schema.md` with the table and the rule (roadmap: before wave 5).
- Extend the two tools and their tests as in section 6, with a LocalDB integration case.
- Register the freshness risk and the cross-machine data in the risk register (task 2) and the threat model (task 4).
