# Engine port specification: MANAGED_ASSETS

**Status:** [PROPOSED] specification for review (task 3, wave 2). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `MANAGED_ASSETS` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-ManagedAssets.ps1`, version `1.0`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `F91CB97A...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `MANAGED_ASSETS`; the procedures `cfg.GetManagedAssetPlan` and `cfg.ReviewManagedAssets`. Script text is not copied.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Put each instance's customer logo (a PNG) at the three places where the applications read it, and verify it by SHA-256. [CONFIRMED] Action: group `CONFIGURATION`, preview and apply, all enabled instances or one, step 40 of `FULL_DEPLOYMENT` (stop on error). The engine is generic in name (`AssetType`) but only `CUSTOMER_LOGO` exists.

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `dbo_ManagedInstance` | `InstanceCode`, `IsEnabled`, `CustomerLogo` (BLOB), `CustomerLogoFileName`, `CustomerLogoMimeType`, `CustomerLogoSha256` |
| `cfg_ManagedAssetDestination` (3 rows) | `AssetType`, `DestinationCode`, `PathTemplate`, `CreateDirectory`, `IsRequired`, `SortOrder`, `IsEnabled` |
| `dbo_ManagedServer` | `MachineName`, `ConfigBackupRoot` |

The three destinations, all under the instance root: the WFM application (`WFM_CUSTOMER_LOGO`), the identity server (`IDENTITY_CUSTOMER_LOGO`) and the SISQUAL View application (`VIEW_CUSTOMER_LOGO`); all with `CreateDirectory` = 1 and required. Parameters: instance (optional), apply.

[CONFIRMED] Data (2026-10-05 snapshot): 62 of 76 instances have a logo; all 62 are PNG, 5.5 to 9.1 KB (482 KB in total), and every stored hash equals the hash of the bytes. The 14 enabled instances **without** a logo are all on PRESALES (8) and TENDERS (6).

## 3. Steps

1. Resolve the machine from the catalog; review the model (codes `ENABLED_INSTANCE_LOGO_MISSING`, `ENABLED_INSTANCE_LOGO_HASH_MISSING`, `ASSET_DESTINATION_MISSING`).
2. Build the plan: each enabled instance of this machine times each enabled destination; the path is the template expanded with the instance (the instance root token).
3. Compare: the SHA-256 of the file at the path with the expected hash: `MISSING` (no file), `DIFFERS`, `MATCHED`.
4. Preview: `MATCHED` or `WOULD_UPDATE` per row; nothing is written. [CONFIRMED] An empty plan is an error ("no enabled managed-asset deployment operations").
5. Apply, per row that is not `MATCHED`: create the destination folder if allowed, back up an existing file, check the catalog bytes are not empty and match the expected hash, write to a temporary file next to the target and move it, re-hash the result; status `UPDATED`.
6. Report one row per instance and destination (instance, destination, path, status, expected and current hash, bytes) to the result and the text log.

## 4. Side effects

Writes up to 3 PNG files per instance (administrator rights); backups and the report under `ConfigBackupRoot\ManagedAssets\CustomerLogos_<timestamp>`. [CONFIRMED] No ACL changes, no service, pool or site restart, no database writes.

## 5. External dependencies

File system only. [V] Whether the identity server and the other applications cache the image and need a restart to show a new one.

## 6. Preview and apply

Preview is deterministic. Apply consumes the fingerprint of the previewed plan and refuses if the catalog or the destinations changed. Statuses follow the engine result contract: `MATCHED`, `WOULD_UPDATE`, `UPDATED`, `ERROR`.

## 7. Idempotency

Compare by hash and write only when different, so a second run is all `MATCHED` and leaves file times untouched. A destination file that has the right bytes under a different name or time is not rewritten.

## 8. Failures

- Missing destination folder and `CreateDirectory` = 0: `ERROR` for that row.
- Empty content or a catalog hash that does not match its bytes: `ERROR`, nothing written.
- A write that fails the post-write hash: `ERROR`, the previous file is restored from the backup.
- [CONFIRMED] The old engine ran in one `try` for the whole loop: the first failure aborted the run and left later rows undone. [PROPOSED] capture errors per row, continue, and fail at the end with the count.
- Instances without a logo: see section 13.

## 9. Backup and restore

Copy each existing destination file before replacing it, to `Backups\<instance>\<destination>` in the run folder. [PROPOSED] a run manifest (path, backup, hashes) and a restore function that copies back and verifies the hash, tested before the engine is enabled (R-033). Backups are small (about 8 KB per file).

## 10. Secret risks

None expected: logos are customer branding, not credentials. Reports contain paths, hashes and byte counts only. A marker test still checks the log and result. The package is not used.

## 11. What does not port as it is

`ops.GetConsoleBootstrap` (the backup root) becomes a catalog read; the plan procedure becomes a local plan builder; the content, name, type and hash come from the instance row of the catalog (a BLOB, byte for byte, hash checked by `Test-CatalogConversion`); the review becomes a local function. The `AssetType` parameter is fixed to the customer logo; other assets (links page, Pulse, branding) belong to other engines.

## 12. Test plan

- Runner: a temporary tree and a synthetic catalog with PNG fixtures: all three destinations; `MISSING`, `DIFFERS`, `MATCHED`; folder creation allowed and forbidden; backup and restore; a read-only file; a locked file; a catalog hash mismatch; empty content; an instance without a logo; instance filter; idempotency (no write, times kept); the per-row error capture; no secret in artifacts (marker).
- [V] A pilot server: the real instance roots and ACLs; whether the applications show the new image; the 14 instances without a logo on PRESALES and TENDERS.

## 13. Open questions

1. [PENDING] An enabled instance without a logo: today the review reports an `ERROR` and apply would stop on it (PRESALES and TENDERS, 14 instances). Recommendation: a `WARNING` ("no logo defined") with no write, so those machines are not blocked by logos; the owner decides.
2. [PENDING] Validate that the bytes are a PNG and within a size limit before writing. Recommendation: yes (PNG signature, 1 MB), reported as an `ERROR` at catalog review.
3. [PENDING] ACLs of the written files. The old engine sets none, so they inherit from the folder. Recommendation: keep, and confirm on the pilot [V].
4. [PENDING] Should the engine also remove logos at destinations when the instance has none? Recommendation: no (never delete).
