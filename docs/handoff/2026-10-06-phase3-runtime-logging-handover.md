# Phase 3 runtime logging handover

**Date:** 2026-10-06
**PR:** #49 `feat/phase3-runtime-logging`
**Status:** [CONFIRMED] implementation validated; PR remains unmerged.

## Resume point

The runtime logging slice is technically complete. Do not restart logging design unless review identifies a defect.

The implementation is intentionally independent of:

- PR #36 SQLite provider adoption;
- B6.2 signer/verifier and issuer-key work;
- the separate `feat/phase3-runtime-bootstrap` branch;
- Pode/web API work;
- engine execution.

## Accepted implementation

`runtime/Sisqual.Runtime.Logging.psm1` implements:

- configurable log root, default `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement`;
- configurable retention, default 30 days;
- one UTF-8/no-BOM file per UTC day;
- retention restricted to matching logger-owned filenames;
- in-process serialized record writes;
- validation of event/property names;
- defence-in-depth redaction for common secret-bearing fields and inline tokens;
- embedded-newline normalization.

Primary safety rule: callers must never supply decrypted secrets or secret-bearing objects. Redaction is a secondary barrier, not an authorization to log secrets.

## Accepted run

- workflow: `phase3-runtime-logging`;
- workflow ID: `375929890`;
- run: `37395610886`;
- run number: `2`;
- attempt: `1`;
- commit: `013bbca2abba690f1f1aef226d1231bc67c75a54`;
- conclusion: success.

Windows 2022:

- job `112050726055`;
- runner `GitHub Actions 1000000675` / ID `1000000675`;
- 20/20 checks PASS.

Windows 2025:

- job `112050726205`;
- runner `GitHub Actions 1000000676` / ID `1000000676`;
- 20/20 checks PASS.

Repository CI on the same commit:

- run `37395616846`;
- CI number `133`;
- job `112050743640`;
- parser PASS;
- ASCII/LF PASS;
- secret scan PASS.

No workflow artifact is expected for the dedicated logger run. The Actions job logs and `docs/phase3/evidence/runtime-logging-37395610886/README.md` are the evidence record.

## Historical first run - preserve it

Dedicated run `37395436558` on commit `fb23127738d22c087bf8560ba6329f82e89e7b43` passed the runtime tests on both Windows versions.

Normal CI run `37395461841`, job `112050250528`, then failed the repository secret scan because the unit test contained a literal password-shaped synthetic fixture. Parser and ASCII/LF were green.

The correct response was not to weaken the scanner. Commit `013bbca2abba690f1f1aef226d1231bc67c75a54` constructs the synthetic fixture at runtime. The second dedicated run and normal CI are both green.

## What not to do

- do not put this logger under `modules/`; runtime modules are allowed to write logs, while engine/plan modules have stricter write constraints;
- do not pass decrypted credential values into `Write-SisqualRuntimeLog` and rely on redaction;
- do not delete unrelated files during retention;
- do not switch the daily filename boundary silently from UTC without an explicit decision;
- do not expand this PR into bootstrap, SQLite, credentials, Pode or engine work;
- do not weaken the repository secret scanner to make test fixtures easier to write.

## Next integration points

[PENDING] The separate runtime bootstrap work should import/initialize this logger after its own architecture is integrated.

[PENDING] Engine execution should log normalized operation start/finish/result fields without secret-bearing parameters.

[PENDING] Decide later what read-only log information, if any, is surfaced through REST/UI.

No merge has been performed by this handover.
