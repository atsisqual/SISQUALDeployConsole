# MANAGED_ASSETS port brief

**Status:** [PROPOSED]
**Task:** T2 / M3.3
**Date:** 2026-10-10

This brief defines the evidence boundary and implementation gate for the `MANAGED_ASSETS` engine. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/MANAGED_ASSETS.md` documents the source-era `Invoke-ManagedAssets.ps1`, action `MANAGED_ASSETS`, `cfg.GetManagedAssetPlan` and `cfg.ReviewManagedAssets`.
- `tests/Fixtures/carried-schema.json` confirms the carried logo fields on `dbo.ManagedInstance` and the `cfg.ManagedAssetDestination` table/columns used by the engine.
- `docs/handoff/preflight-port-gap.md` on PR #69 says `cfg.ReviewManagedAssets` is complete by original issue-code coverage and counts one original review code. This is important because the current engine specification also names direct validation findings; those must not be relabelled as original review codes without source evidence.
- Rules 6 and 7 on PR #69 apply: cross-instance invariants use every enabled instance where relevant; catalog-derived paths must remain under the approved root after link/junction resolution.

[NOT VERIFIED] The original engine/procedure text was not re-extracted or executed for this brief. Source-era counts and behavior below are taken from the existing specification and must be rechecked mechanically by the implementation reviewer.

## 2. Purpose and scope

[CONFIRMED] `MANAGED_ASSETS` is `MUTATING`. Its current specification limits the engine to publishing the customer logo carried by each enabled managed instance to the configured managed-asset destinations.

[CONFIRMED] The existing specification records three destination roles: WFM customer logo, Identity customer logo and SISQUAL View customer logo. The engine previews hash state, then on apply creates allowed destination directories when policy permits, backs up an existing different file, writes the catalog BLOB, and verifies the written SHA-256.

[PROPOSED] Keep the first portable port narrowly scoped to these catalog-driven assets. Do not generalize it into arbitrary file deployment or application update logic.

## 3. Catalog inputs confirmed by carried schema

| Table | Columns used by the port |
|---|---|
| `dbo.ManagedInstance` | `InstanceCode`, `IsEnabled`, `CustomerLogo`, `CustomerLogoFileName`, `CustomerLogoMimeType`, `CustomerLogoSha256`, plus instance/root fields needed by approved path-template expansion |
| `cfg.ManagedAssetDestination` | `AssetType`, `DestinationCode`, `PathTemplate`, `CreateDirectory`, `IsRequired`, `SortOrder`, `IsEnabled` |
| `dbo.ManagedServer` | machine identity and `ConfigBackupRoot` as named by the current specification |

[CONFIRMED from the existing specification] The reference configuration contains three managed-asset destinations. That is an evidence count, not a hard-coded universal assertion: code must consume enabled catalog rows and validate required destination policy.

## 4. Credentials and network

[CONFIRMED] No credential reference is required by the current engine specification.

[PROPOSED] The port performs no network call. A catalog path that resolves to UNC/device/network syntax is rejected before probing. The engine operates only inside approved local roots.

## 5. Old behavior, step by step

The existing specification records this behavior:

1. Resolve the local machine and the selected enabled instance(s).
2. Validate that required asset metadata/destinations exist before building the plan.
3. Expand each enabled destination path for each selected instance.
4. Validate containment before probing the destination.
5. Compute/compare SHA-256 rather than comparing by timestamp.
6. Preview one row per instance/destination with a no-write state such as matched, missing/would-create or different/would-update.
7. APPLY creates the destination directory only where `CreateDirectory` permits it.
8. Before replacing an existing different file, save a backup and record its hash.
9. Write the exact catalog BLOB atomically and recompute the destination SHA-256.
10. Fail the item if post-write hash differs from `CustomerLogoSha256`; emit structured rows and text logs without embedding binary content.

## 6. Original findings versus engine validations

[CONFIRMED] The current `MANAGED_ASSETS` specification names the findings `ENABLED_INSTANCE_LOGO_MISSING`, `ENABLED_INSTANCE_LOGO_HASH_MISSING` and `ASSET_DESTINATION_MISSING` as model/plan validations.

[CONFIRMED] The PR #69 gap inventory separately says the original `cfg.ReviewManagedAssets` contributes one original issue code and that this review is already complete by code in the integrated preflight.

[PROPOSED] Treat these as two evidence categories until the source procedure is rechecked:

- original `cfg.ReviewManagedAssets` issue code/severity: authority is the source evidence;
- engine-local preconditions/findings used to make asset deployment safe: authority is the port specification and explicit owner decisions.

[PENDING] The code PR must name the one original review code and its exact severity from the approved evidence instead of inferring it from these three labels.

## 7. Path and cross-instance rules

[PROPOSED] For every destination:

- build the lexical path from catalog data without touching the network;
- reject non-local, device and UNC paths;
- require the lexical path to stay under the approved instance/application asset root;
- resolve existing junctions/symbolic links and require the real path to remain under the same root;
- treat access denied as an item `ERROR`, not an unstructured exception.

[PROPOSED] This engine does not appear to have a natural cross-instance uniqueness predicate in the current specification. If the original source introduces one, rule 6 from PR #69 applies: compare the selected instance against every enabled instance on the machine, not just selected instances.

## 8. Side effects, backup and restore

[CONFIRMED] Managed side effects are limited to creating configured local directories and creating/replacing managed asset files. No database, service, scheduled-task or IIS configuration write belongs here.

[PROPOSED] APPLY requires the exact confirmed preview fingerprint. For each existing file that will be changed, back up original bytes once, record SHA-256 and target identity, then use same-directory atomic replacement where possible. Restore must verify the restored hash.

[PROPOSED] Never delete an old/stale asset merely because a destination row disappears unless a separate owner decision explicitly introduces deletion semantics.

## 9. Result contract

[PROPOSED] One result row per selected instance and enabled destination, deterministic by instance and `SortOrder`/`DestinationCode`. The row should carry the destination identity, non-secret path/object identity and one of the engine's approved status values. Binary logo data never appears in the result or log.

A required destination fails closed when:

- logo BLOB or expected hash required by source policy is absent;
- target path escapes containment or cannot be read/written;
- required parent directory cannot be created;
- backup fails before replacement;
- atomic write fails;
- post-write SHA-256 is not exactly the expected catalog hash.

## 10. Required tests

The code PR must cover at minimum:

- selected instance and all enabled instances;
- each of the three reference destination roles without hard-coding their count as the only valid catalog shape;
- missing logo BLOB, missing expected hash and missing required destination policy;
- matched hash, absent destination and different destination hash;
- optional versus required destination behavior;
- `CreateDirectory = 0` and `CreateDirectory = 1`;
- path containment including `..`, absolute-path injection, UNC/device path and a junction/symlink leaving the root;
- access denied reported as an item error;
- preview has no managed write;
- preview/apply fingerprint mismatch blocks apply;
- backup before replacement and restore hash verification;
- post-write hash mismatch;
- idempotency: second run produces no managed write;
- deterministic row ordering;
- source-evidence test for the exact original `cfg.ReviewManagedAssets` issue code and severity.

[V] A real-server proof is still required for the actual destination roots, ACLs and application consumption of the logo.

## 11. Open questions

1. [PENDING] Exact original `cfg.ReviewManagedAssets` code, predicate and severity from the approved source evidence.
2. [PENDING] Whether missing logo metadata is blocking for every enabled instance or only for instances/destinations marked required by source policy.
3. [PENDING] Whether MIME/file-name validation is purely metadata validation or must reject non-PNG bytes; do not infer this from the `.png` convention.
4. [PENDING] Backup retention and ACL policy.
5. [PENDING] Whether an obsolete destination file is ever deleted. Recommendation: no deletion in the first port.

## 12. Entry gate for the code PR

The `MANAGED_ASSETS` code PR may start when:

- the original review code/severity is identified from source evidence;
- every table/column used by code is present in `tests/Fixtures/carried-schema.json`;
- the approved root for every destination template is explicit and testable;
- backup/restore policy is sufficient to reverse every replacement;
- required/optional semantics for missing logo data are confirmed;
- the reviewer has a fixture mapping each source finding and each safe-deployment failure path to a positive and negative test.
