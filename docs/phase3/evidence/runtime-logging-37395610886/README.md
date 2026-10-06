# Phase 3 runtime logging evidence - run 37395610886

**Workflow:** `phase3-runtime-logging`
**Workflow ID:** `375929890`
**Run ID:** `37395610886`
**Run number:** `2`
**Attempt:** `1`
**Event:** `push`
**Branch:** `feat/phase3-runtime-logging`
**Commit:** `013bbca2abba690f1f1aef226d1231bc67c75a54`
**PR:** #49
**Created UTC:** `2026-10-06T00:45:01Z`
**Completed UTC:** `2026-10-06T00:45:22Z`
**Status:** [CONFIRMED] accepted technical evidence for the Phase 3 runtime logging foundation.

## Execution ledger

| OS | Job ID | Runner | Runner ID | Started UTC | Completed UTC | Result |
|---|---:|---|---:|---|---|---|
| windows-2022 | `112050726055` | `GitHub Actions 1000000675` | `1000000675` | 2026-10-06T00:45:04Z | 2026-10-06T00:45:20Z | success |
| windows-2025 | `112050726205` | `GitHub Actions 1000000676` | `1000000676` | 2026-10-06T00:45:04Z | 2026-10-06T00:45:22Z | success |

[CONFIRMED] Both jobs completed every workflow step successfully: checkout, download and SHA-256 verification of portable PowerShell 7.6.6, execution of the runtime logging unit tests, and job cleanup.

[CONFIRMED] The workflow produced no GitHub artifact by design. The immutable Actions logs are the execution evidence for this small unit-runtime slice.

## Unit result

[CONFIRMED] Both Windows jobs reported `20 passed, 0 failed`.

The checks cover:

- ADR-0007 default log root;
- 30-day default retention;
- stable log prefix;
- configured directory creation;
- canonical configured path;
- configured retention value;
- removal of expired matching log files;
- preservation of the retention-boundary day;
- preservation of unrelated files;
- expected daily filename;
- safe context preservation;
- sensitive property-name redaction;
- inline token/authorization redaction;
- bearer-token redaction;
- absence of supplied test secret values;
- one physical line per log call;
- UTF-8 without BOM;
- UTC daily rotation;
- invalid event-code rejection;
- unsafe property-name rejection.

## Runtime pin

[CONFIRMED] Each job downloaded `PowerShell-7.6.6-win-x64.zip` and verified SHA-256:

`02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860`

The tests were launched using the verified portable `pwsh.exe`, not the runner-installed PowerShell.

## Repository CI

[CONFIRMED] CI run `37395616846`, CI number `133`, job `112050743640`, passed on the same commit. Its parser, ASCII/LF and simple secret-scan steps all succeeded.

## Superseded first execution

[CONFIRMED] Dedicated run `37395436558`, run number `1`, commit `fb23127738d22c087bf8560ba6329f82e89e7b43`, passed the runtime tests on both Windows versions.

[CONFIRMED] Repository CI run `37395461841`, job `112050250528`, failed only the simple secret-scan step because the unit fixture contained a literal password-shaped synthetic value. PowerShell parsing and ASCII/LF checks passed.

[CONFIRMED] The secret scanner was not relaxed. Commit `013bbca2abba690f1f1aef226d1231bc67c75a54` changed the fixture to construct its synthetic sensitive key/value at runtime. Run `37395610886` and CI `37395616846` are therefore the accepted combination.

## Acceptance boundary

[CONFIRMED] The runtime logger implementation is technically viable for the tested scope on Windows Server 2022 and 2025 under portable PowerShell 7.6.6.

[PENDING] Integration into the real startup/bootstrap runtime.

[PENDING] Integration of normalized engine operation events.

No claim is made that redaction makes arbitrary secret-bearing input safe. Callers remain responsible for never supplying decrypted secrets to the logger.
