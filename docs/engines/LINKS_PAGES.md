# Engine port specification: LINKS_PAGES

**Status:** [PROPOSED] specification for review (task 3, wave 5). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `LINKS_PAGES` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-LinksPageDeployment.ps1`, version `7.1`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `0677CE69...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `LINKS_PAGES`; the procedures `cfg.GetLinksPageDeploymentPlan`, `cfg.GetLinksPageItemPlan`, the resource plans, the reviews and `cfg.SyncLinksPageInstanceApplications`; the design of the instance directory (task 1c, PR #29). Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Write the `/links` pages: for every instance a page in its own IIS site under the `links` folder, and, for the instances with `LinksIncludeAllInstances` = 1, a general page listing every enabled instance of the country (owner decision of 2026-10-05: general page on the main instance, individual page in each site). [CONFIRMED] Action: group `ACCESS`, preview and apply, all enabled instances or one, step 80 (last) of `FULL_DEPLOYMENT`. A links policy exists on 4 machines; PRESALES and TENDERS stop with "policy missing".

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `cfg_LinksPagePolicy` (1 per machine) | `RelativePath` (`links`), titles, `ShowSearchWhenMultipleEnvironments` |
| `cfg_LinksPageTemplate` (2) | the index page (about 15 KB) and a web config, with SHA-256 |
| `cfg_LinksPagePresentationResource` (21) | 10 icons, 7 texts, 4 components, with hashes |
| `cfg_LinksPageAsset` (45) | 44 QR images (by customer code) and 1 logo |
| `cfg_WebsiteBrandingProfile`, `cfg_WebsiteBrandingAsset` (global) | title templates and 3 favicon files |
| `cfg_Application` | the 12 applications published in links, with link templates |
| `cfg_LinksPageInstanceApplication`, `cfg_LinksProfile`, `cfg_LinksProfileInstance`, `cfg_LinksProfileApplication` | visibility for individual pages |
| `dbo_ManagedInstance` and the instance directory | `InstanceCode`, `HostName`, `CountryCode`, `CustomerCode`, `CustomerName`, assigned user name; other machines' instances from `cfg_LinksPageDirectory` (design of task 1c) |

Model review: the 8 issue codes of the links model, the presentation hash check, and the QR checks (`QR_ASSET_MISSING`, `QR_ASSET_UNASSIGNED`, `QR_CONTENT_HASH_MISMATCH`).

## 3. Steps

1. Review the model locally (stop on errors); resolve the page instances of this machine and, for each, the target instances and applications (rule of the 1c design: general pages take the same-country instances of all machines, individual pages only themselves; a hub application only on its hub's page).
2. Render the page from the template with HTML-escaped values and the environment blocks, search block and QR images; an unresolved token is an error.
3. Preview: one row per page with counts (environments, applications, QR codes, branding assets). [CONFIRMED] It does not say which files would change.
4. Apply: create the folders; for each of index, web config, logo, QR images and branding files, compare the SHA-256 and, if different, back up and write atomically, then verify the branding files; report `UPDATED` or `MATCHED`.

## 4. Side effects

Writes files in each instance's links folder and the branding files in the website root (shared with the Pulse page); backups and a report. No IIS configuration is changed (the folder is served by the existing site).

## 5. External dependencies

File system only (the site folders); IIS must already serve them (`IIS_RECONCILE`).

## 6. Preview and apply

[PROPOSED] A real preview listing the files that would change, the directory rows used and the catalog build date (risk R-044). Apply consumes the fingerprint of the preview.

## 7. Idempotency

[CONFIRMED, defect] The page contains a generation time, so its hash differs on every run: the index is rewritten and backed up on every apply and the status is never `MATCHED`. [PROPOSED] Keep the generation time out of the compared content (render it from a fixed value for comparison, or write it into a file the page reads), so a second apply with no change reports `MATCHED` and writes nothing.

## 8. Failures

A missing links folder parent, a failed write or a hash mismatch after a branding write: error for that instance, the others continue, the run fails at the end. A target instance with no QR image where required is a review error. An instance in the directory that no longer exists is only discovered by a new conversion (R-044).

## 9. Backup and restore

Each replaced file is copied to a per-instance backup folder first. [PROPOSED] A run manifest with before and after hashes and a restore that copies back and checks the hash (R-033).

## 10. Secret risks

None expected: the pages are public. [CONFIRMED] No link template uses a secret token and the engine never reads one. Values are HTML-escaped (test ST-14 of the threat model: markup in a customer name must not become markup). The assigned user name is printed on the page (open point of the 1c design).

## 11. What does not port as it is

The plan procedures become a plan builder over the catalog and the directory. `cfg.SyncLinksPageInstanceApplications` inserted default visibility rows into the central table; the catalog is read-only, so the default (the application's `LinksDefaultForIndividualPages`) is computed in memory. The old report folder and the SQL context go.

## 12. Test plan

- Runner: a synthetic catalog with several machines' instances; general and individual pages; the hub rule; markup and script in names, titles and host names; unresolved token; QR present and missing; idempotency (no write on a second apply, no backup); backup and restore; preview lists exactly the files apply changes; branding hash check.
- [V] Real servers and browsers; the pages as served by the real sites.

## 13. Open questions

1. [PENDING] The generation time (section 7). Recommendation: remove it from the compared content.
2. [PENDING] Machines without a policy that have a general page instance (PRESALES, TENDERS): they stop with "policy missing" as decided; confirm that is intended for the pilot.
3. [PENDING] The assigned user name on the page (task 1c).
4. [PENDING] The 5 obsolete profile-instance rows are not carried; confirm no page depends on them (owner decided they are obsolete).

## Host contract

- Engine class: `MUTATING`.
- Credential references: none.
