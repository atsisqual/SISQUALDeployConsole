# LINKS_PAGES port brief

**Status:** [PROPOSED]
**Task:** T9 / M3.6
**Date:** 2026-10-10

This brief defines the implementation gate for the `LINKS_PAGES` port. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/LINKS_PAGES.md` documents source-era `Invoke-LinksPageDeployment.ps1`, the Links plan/review procedures and the old central visibility sync.
- `docs/migration/instance-directory-design.md` is implemented C1/C2 design: a local general page can use the derived `cfg_LinksPageDirectory`; individual pages use only their own instance; the directory contains only seven public fields and no secrets/ports/paths.
- The current specification identifies the Links model, presentation hash and QR review families and the catalog tables for policy/templates/resources/assets/branding/applications/profiles.
- PR #69 containment applies to every generated/written path. Catalog codes are exact; public text is HTML-escaped.

[NOT VERIFIED] The original Links script/procedures were not re-extracted or rendered in a real browser for this brief. Real-site/browser behavior remains `[V]`.

## 2. Purpose and class

[CONFIRMED] `LINKS_PAGES` is `MUTATING`. It writes an individual `/links` page in each selected instance site and, where `LinksIncludeAllInstances = 1`, a general page containing same-country enabled instances across machines.

[CONFIRMED] It has no credential references, changes files only, relies on IIS already serving the folder, and is step 80 (last) of `FULL_DEPLOYMENT`.

## 3. Catalog inputs

The port consumes the carried/derived model documented by the specification:

- `cfg.LinksPagePolicy` - machine policy including relative path/title/search behavior;
- `cfg.LinksPageTemplate` - index and web-config templates with hashes;
- `cfg.LinksPagePresentationResource` - icons/text/components with hashes;
- `cfg.LinksPageAsset` - QR assets and logo;
- website-branding profile/assets;
- `cfg.Application` published-link metadata;
- `cfg.LinksPageInstanceApplication`, `cfg.LinksProfile`, `cfg.LinksProfileInstance`, `cfg.LinksProfileApplication` for individual visibility;
- local `dbo.ManagedInstance` rows;
- derived `cfg_LinksPageDirectory` for permitted remote public instance rows.

[CONFIRMED] `cfg_LinksPageDirectory` is not a central/runtime sync channel. Conversion derives it and the verifier independently checks it; catalogs without an enabled general page have the table present but empty.

## 4. General versus individual page scope

[CONFIRMED] Individual page: target is the page instance itself and visibility layers can filter its applications.

[CONFIRMED] General page: targets are every enabled instance of the same country from enabled machines; remote targets come only from the derived directory. All published applications show for each target under source behavior, subject to the hub rule.

[CONFIRMED] `LinksHubInstanceCode` is not resolved through the directory. A hub application is shown only on its own hub instance/page; other catalogs require no extra remote hub data.

[PROPOSED] Runtime code must never reach out to another machine/catalog to refresh a page. Directory freshness is a conversion/reseal concern, not an engine network dependency.

## 5. Public-data and escaping rules

[CONFIRMED] The directory carries only `InstanceCode`, `ServerCode`, `CountryCode`, nullable `CustomerCode`, nullable `CustomerName`, `HostName`, nullable `AssignedUserName`. The public page already displays the assigned username by owner decision C1.

[PROPOSED] Every catalog/directory string placed into HTML, attributes, URLs or scripts is encoded for its output context. A customer/title/user/host value containing markup must remain text, never active markup/script. Do not infer safety from source trust.

No credential/token is read. A secret-like marker in catalog public text should still be treated as ordinary escaped text; the engine must not have credential-package access.

## 6. Model reviews

[CONFIRMED] The specification requires:

- the eight original Links-model issue codes;
- `LINKS_PRESENTATION_HASH_MISMATCH` from presentation resources;
- QR checks `QR_ASSET_MISSING`, `QR_ASSET_UNASSIGNED`, `QR_CONTENT_HASH_MISMATCH`.

[PENDING] The code PR must bind the complete eight-code Links-model list and exact severities/predicates to approved source evidence. Names from a gap inventory are not enough to recreate predicates.

## 7. Desired-state preview

[CONFIRMED, source-era limitation] The old preview gave page-level counts but did not enumerate exactly which files would change.

[PROPOSED] Preview emits a deterministic file plan per page:

- page instance and page type (individual/general);
- exact local/derived target rows used;
- rendered index hash;
- web-config/template/resource/branding/QR files and expected hashes;
- per-file current status `MATCHED`, `WOULD_CREATE` or `WOULD_UPDATE`;
- catalog build/provenance time for operator awareness.

APPLY changes exactly this fingerprinted plan or refuses on catalog/file drift.

## 8. Generation-time idempotency

[CONFIRMED, source-era defect] The rendered page contains generation time, which makes the index hash change on every run.

[PROPOSED] Deterministic compared content must not contain a fresh timestamp. Either omit generation time from compared bytes or render it from a value fixed by the confirmed plan/catalog. A second APPLY with unchanged catalog/directory/assets writes no file and creates no backup.

## 9. Path containment and writes

[PROPOSED] The policy's `RelativePath` and every target asset path are resolved under the approved instance/site root. Reject absolute injection, `..`, UNC/device syntax and reparse-point escape before probing/writing. Branding files written in a shared website root have their own explicit approved root.

APPLY creates only approved folders, backs up a file before replacing it, writes atomically in the same directory, then verifies SHA-256. It does not change IIS configuration.

## 10. Shared branding interaction

[CONFIRMED] The specification notes branding files in the website root are shared with the Pulse page.

[PROPOSED] A shared file has one desired content/hash across engines. Before `LINKS_PAGES` changes a shared branding file, the catalog model must prove the same approved content expected by other consumers; engine ordering must not cause two engines to fight over bytes. Conflicting desired hashes are a model error, not last-writer-wins behavior.

## 11. Backup and restore

[CONFIRMED] Source behavior backs up replaced files per instance.

[PROPOSED] The run manifest records page/file identity, approved root, before hash, after hash and backup object. Restore copies back only when the current file still belongs to the operation or the operator explicitly confirms drift, then verifies the restored hash. Newly created files are removed on restore only when ownership is provable from the manifest.

## 12. Failure/result semantics

Blocking failures include model-review errors, unresolved template tokens, required QR/resource absence, path containment/access failure, atomic-write failure and post-write hash mismatch.

[PROPOSED] Result rows are per file, not merely per page, so preview and APPLY can be compared exactly. Page-level summary counts are additional metadata. Independent selected pages may continue after one page fails where no shared-file dependency makes continuation unsafe; overall run fails on any blocking error.

## 13. Required tests

Runner tests must cover:

- individual page with only itself;
- general page with local plus same-country remote directory rows;
- remote different-country row excluded;
- catalog with no general page has empty directory and no remote consumption;
- hub-application rule without resolving hub through directory;
- nullable customer code/name fallbacks;
- assigned username rendered as approved public data;
- HTML/script/attribute injection strings escaped correctly;
- complete Links model/presentation/QR review cases;
- QR asset present/missing/unassigned/hash mismatch;
- deterministic generation-time behavior and second-run no-op;
- preview enumerates exactly files APPLY changes;
- path traversal/absolute/UNC/device/reparse escape/access denied;
- backup, atomic write, hash verification and restore;
- shared branding same-hash success and conflicting desired-hash model failure;
- stale directory changes produce fingerprint drift rather than runtime remote lookup.

[V] Real IIS sites/browser rendering and final six-catalog reconciliation before cutover.

## 14. Open questions

1. [PENDING] Final deterministic treatment of generation time.
2. [PENDING] Confirm pilot behavior for machines with no Links policy; current decision/source says policy missing is blocking.
3. [CONFIRMED] Assigned username is intentionally public under C1; no new privacy decision is invented here.
4. [PENDING] Prove no page depends on the obsolete profile-instance rows that conversion does not carry.
5. [PENDING] Shared branding ownership/order with the Pulse page when both engines target the same file.

## 15. Entry gate for the code PR

The code PR may start when:

- every used carried/derived table/column is confirmed;
- the eight Links-model predicates/severities plus presentation/QR checks are attached to tests;
- general-page scope is implemented solely from local rows plus verified derived directory;
- deterministic generation-time semantics are decided;
- all output contexts have escaping tests;
- path containment and shared-file desired-state rules are explicit;
- preview is file-exact and restore is hash-verifiable.
