# V8_KEYCLOAK_PREREQUISITES port brief

**Status:** [PROPOSED]
**Task:** T5 / M3.5
**Date:** 2026-10-10

This brief defines the implementation boundary for `V8_KEYCLOAK_PREREQUISITES`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/V8_KEYCLOAK_PREREQUISITES.md` documents the source-era v7 prerequisite engine and its machine-wide action.
- `docs/roadmap.md` and `docs/decisions-log.md` record the owner decision of 2026-10-06: installers come from an operator-provided folder at fixed versions; every artifact is verified by SHA-256 before use; Keycloak requires exactly JDK 23, with no LTS substitution, dynamic selection or `latest`.
- The current engine specification says the legacy engine had no catalog inputs and hard-coded its installer search/version behavior.

[NOT VERIFIED] This brief did not execute the real NSSM/JDK/JDBC installers or re-read the source script. Real silent switches, installed-file layout and machine effects remain `[V]` evidence.

## 2. Purpose and class

[CONFIRMED] `V8_KEYCLOAK_PREREQUISITES` is `MUTATING` and machine-wide. It establishes three prerequisites for the V8 Keycloak service:

1. NSSM service wrapper;
2. exactly JDK 23 for Windows x64;
3. SQL Server JDBC integrated-authentication library, documented source version 12.8.1 x64.

[CONFIRMED] It is step 12 of `FULL_DEPLOYMENT` and has no instance selection or credential reference.

## 3. Owner-decided installer contract

[DECIDED 2026-10-06] The implementation contract is stricter than the old script:

- source directory is supplied by the operator; the fixed legacy drive-letter search is removed;
- artifact versions are fixed, not discovered dynamically;
- each source artifact must match an approved SHA-256 before any elevated execution/copy;
- JDK is exactly version 23; do not substitute an LTS release, choose a newer JDK, or resolve `latest`;
- a source that does not match the approved identity is treated as missing/untrusted, not as an alternative candidate.

[PENDING] The repository currently needs one authoritative place for the approved prerequisite artifact identities (logical item, exact filename/version, SHA-256 and any publisher-signature requirement). Do not invent a new catalog table unless its schema/change is separately approved.

## 4. Portable preview/apply semantics

[CONFIRMED, source-era defect] The old engine installed prerequisites even when invoked as preview.

[PROPOSED] V1 must have a real no-write preview. For each prerequisite it reports one of:

- `MATCHED`: exact required version/identity is already present;
- `WOULD_INSTALL`: target is absent/wrong and the exact verified source is available;
- `MISSING_SOURCE`: required source is absent;
- `SOURCE_HASH_MISMATCH`: a candidate exists but is not the approved artifact;
- `INSTALLED`: APPLY installed/copied and post-verification passed;
- `ERROR`: install/copy/post-verification failed.

Preview must not extract, install, copy to system locations or leave temporary payloads behind.

## 5. Detection contract

[PROPOSED] Presence is not a folder-name check alone:

- NSSM: verify the expected executable at the approved target and, where feasible, its version/hash;
- JDK 23: verify the installed JDK identity/version and required executable layout, not merely a matching directory name;
- JDBC integrated-auth library: verify exact target file identity/version/hash.

A half-installed or wrong-version target is drift and requires correction; it is never reported as matched.

## 6. Apply order and side effects

[CONFIRMED] APPLY may:

- create the NSSM target directory and copy the 64-bit wrapper;
- run the JDK 23 installer elevated and wait for completion;
- copy the JDBC integrated-auth library into its approved target (the legacy target is a Windows system directory);
- use temporary extraction space.

[PROPOSED] Process one item at a time and stop before later items after a blocking failure. Verify each item immediately after mutation. Temporary extraction content is deleted on success and failure when safe.

## 7. Supply-chain and process safety

[PROPOSED] Before any installer is run:

1. resolve the operator folder as a local path;
2. open the exact expected source file only;
3. compute SHA-256 and compare exactly with the approved value;
4. for the JDK installer, also validate the expected publisher signature if that requirement is approved;
5. log only artifact name/version/hash and validation state;
6. invoke without shell interpolation of untrusted paths and capture exit code.

No executable from the operator folder is trusted merely because of its filename.

## 8. Path containment

[PROPOSED] The operator folder and all local target paths are local absolute paths. Reject UNC/device paths before probing. Temporary extraction and copy targets must remain under their approved roots after resolving reparse points. This follows the containment principle of PR #69 even though the paths are machine-wide rather than instance-scoped.

## 9. Backup and restore

[CONFIRMED] Installing JDK/NSSM is not automatically undone by the legacy engine.

[PROPOSED] V1 records exactly what it changed. It does not automatically uninstall system-wide prerequisites as rollback. For a target library that will be replaced, back up the previous file and hash before copy and provide a verified file restore. If NSSM target existed with different bytes, back it up before replacement too.

The result/runbook must state that JDK uninstall is an operator action, not transactional rollback.

## 10. Credentials and secrets

[CONFIRMED] No credentials are required.

The security risk is elevated supply-chain execution, not secret leakage. Logs/results must not include environment dumps or arbitrary installer output that could incidentally expose machine data; capture only bounded/redacted diagnostics needed for failure triage.

## 11. Tests required before code review

Runner tests must cover:

- preview makes no managed change and leaves no extracted payload;
- each item already matched;
- source missing;
- wrong source filename/version;
- SHA-256 mismatch blocks before execution;
- JDK publisher-signature pass/fail if signature checking is part of the approved contract;
- fake NSSM install success/failure and post-copy hash check;
- fake JDK silent install success, non-zero exit, timeout and post-install version mismatch;
- JDBC library copy, replacement backup, post-copy mismatch and restore;
- local-path validation including UNC/device/reparse escape;
- idempotent second apply;
- exact JDK 23 selection: prove an installed/source JDK 21 or 25 is not accepted as a substitute;
- cleanup after success and failure;
- structured results contain exact artifact identity/hash but no arbitrary installer transcript.

[V] Clean-server run with the real chosen NSSM, exact JDK 23 package and SQL JDBC integrated-auth library, including the real silent switches and target discovery.

## 12. Open questions

1. [PENDING] Authoritative storage for approved installer filenames/versions/SHA-256 values. The owner decided the semantics, not necessarily the storage shape.
2. [PENDING] Whether JDK publisher signature validation is mandatory in addition to SHA-256.
3. [PENDING] Whether the JDBC integrated-auth library can live beside the Keycloak/JDBC files instead of the Windows system directory. Preserve the current system-directory target until evidence proves an alternative.
4. [PENDING] Exact timeout and acceptable restart/reboot behavior of the chosen JDK 23 installer.

## 13. Entry gate for the code PR

The code PR may start when:

- exact prerequisite artifacts and approved SHA-256 values have an authoritative source;
- the operator-folder input contract is fixed and local-path constrained;
- exact JDK 23 detection/install verification is specified;
- the JDBC target-location decision is either closed or the legacy target is explicitly retained;
- fake-installer runner tests cover preview, apply, failure and idempotency;
- `[V]` real-installer validation remains explicitly outside runner acceptance rather than being assumed.
