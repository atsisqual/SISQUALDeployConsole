# Phase 1B validation handover - 2026-10-05

**Purpose:** allow another AI/reviewer or a human to continue the Phase 1B validation work without reconstructing context from chat history.

**Status:** [CONFIRMED] handover snapshot for PR #36 and PR #37 as of 2026-10-05. This is a working handover, not a decision record. Do not use it to promote [PROPOSED] contract choices to [CONFIRMED].

**Repository:** `atsisqual/SISQUALDeployConsole`

## 1. Read this first

1. Read current `AGENTS.md`, `docs/decisions-log.md`, the relevant ADRs/contracts and list all open PRs before making changes.
2. Do not modify `atsisqual/SISQUALManagementConsole`; it is read-only reference evidence.
3. Do not merge PRs unless the owner explicitly delegates merge authority.
4. Use `[CONFIRMED]`, `[PROPOSED]`, `[PENDING]`, `[V]` exactly as defined by repository rules.
5. All PowerShell is PowerShell 7 unless an ADR explicitly designates a Windows PowerShell 5.1 fallback child.
6. Never commit or print real credentials, tokens, private keys or production connection strings.

## 2. Executive state

Two Phase 1B validation threads were handled in this session.

### PR #36 - SQLite/provider validation

[CONFIRMED] PR #36 was not given a technical PASS/FAIL because three GitHub-hosted Windows attempts did not receive a runner and executed zero probe steps.

[CONFIRMED] The attempts, run/job identifiers and the infrastructure-only conclusion are documented in PR #36. Do not reinterpret runner starvation as a SQLite/provider failure.

[PROPOSED] Leave PR #36 for another reviewer/AI or a later runner window. If retried, preserve the existing evidence and add a new attempt/run record rather than rewriting history.

### PR #37 - CNG machine identity

**PR:** `#37` - `spike(phase1b): validate non-exportable CNG machine identity`

**Branch:** `spike/phase1b-machine-identity-cng`

**Base:** `main` at `ad598215fe3ab0bc715a797a37e2bcf9331eaa56`

[CONFIRMED] PR #37 is technically successful. The CNG candidate passed a two-VM test on GitHub-hosted Windows Server 2022 and Windows Server 2025.

[PROPOSED] Adoption of CNG for V1 machine identity is still a product/contract decision. Technical success does not by itself approve the credential contract.

## 3. Accepted CNG technical evidence

**Workflow:** `phase1b-machine-identity`

**Workflow ID:** `375831032`

**Accepted run:**

- run ID: `37377769448`
- run number: `3`
- run attempt: `1`
- event: `push`
- tested commit: `09de75cb90eedc6015e7125d54da0d25253052c7`
- conclusion: `success`

### Machine A

- OS/runner label: `windows-2022`
- job ID: `111991358773`
- runner name: `GitHub Actions 1000000539`
- runner ID: `1000000539`
- artifact ID: `11373000213`
- artifact size: `10931` bytes
- artifact SHA-256: `a8ffa576c2331b555f9e15cb841c071c14eb058c8fca56863b4203d07fdcb132`

[CONFIRMED] Machine A passed:

- unique key absent before create;
- machine-scope CNG key;
- `Microsoft Software Key Storage Provider`;
- ECDH P-256;
- export policy `None`;
- public SPKI export;
- PKCS#8 private export blocked;
- CNG private-blob export blocked;
- `Sisqual.Credentials` encrypt/decrypt interop;
- reopen in a later process;
- replacement of the portable folder while preserving the same fingerprint;
- explicit key cleanup.

### Machine B

- OS/runner label: `windows-2025`
- job ID: `111992501724`
- runner name: `GitHub Actions 1000000542`
- runner ID: `1000000542`
- artifact ID: `11373310252`
- artifact size: `1188` bytes
- artifact SHA-256: `fddf5bb8175218c851ed102c90284e82cac922d6ea460bd4b6261ec9e67f4579`

[CONFIRMED] Machine B downloaded the exact Machine A artifact and GitHub verified its digest before use.

[CONFIRMED] Machine B passed:

- copied portable folder did not contain/open Machine A private key;
- same logical key name created a different local identity/fingerprint;
- private exports remained blocked;
- local `Sisqual.Credentials` interop;
- credential entry encrypted to Machine A was rejected on Machine B (`SOURCE_ENTRY_REJECTED_ON_DESTINATION`);
- explicit key cleanup.

## 4. Preserved failed harness runs

These are historical harness failures and must remain visible.

### Run `37376755238`

- run number `1`, attempt `1`
- commit `53cccd67cee9cd5e2cd9a9210995a6987c563adf`
- Machine A job `111987660696`
- Machine B job `111988756769` skipped

[CONFIRMED] Failure occurred before CNG key creation because an empty generic check list was enumerated through the PowerShell pipeline and `$checks` became `$null`.

### Run `37377236061`

- run number `2`, attempt `1`
- commit `3df9c920409b9061cf34f4f88ebdd0f28001809f`
- Machine A job `111989440871`
- Machine B job `111990541311` skipped

[CONFIRMED] Failure occurred before CNG key creation because PowerShell rejected an empty collection for a mandatory parameter before `[AllowEmptyCollection()]` was added.

Do not classify either run as a CNG technical failure.

## 5. Evidence locations

Primary design/status document:

- `docs/phase1/phase1b-machine-identity-cng.md`

Live evidence ledger:

- `docs/phase1/evidence/phase1b-machine-identity/README.md`

Accepted run evidence:

- `docs/phase1/evidence/phase1b-machine-identity-37377769448/README.md`
- `docs/phase1/evidence/phase1b-machine-identity-37377769448/report-machine-a-create.json`
- `docs/phase1/evidence/phase1b-machine-identity-37377769448/report-machine-a-reopen.json`
- `docs/phase1/evidence/phase1b-machine-identity-37377769448/report-machine-a-cleanup.json`
- `docs/phase1/evidence/phase1b-machine-identity-37377769448/report-machine-b.json`
- `docs/phase1/evidence/phase1b-machine-identity-37377769448/report-machine-b-cleanup.json`

Historical failed-run evidence:

- `docs/phase1/evidence/phase1b-machine-identity-37376755238/README.md`
- `docs/phase1/evidence/phase1b-machine-identity-37377236061/README.md`

The original workflow artifacts remain the authoritative full artifact copies. The repository intentionally does not need to version the full public SPKI identity file to prove the gates; artifact ID + digest and the gate reports are preserved.

## 6. Final static CI state before this handover commit

[CONFIRMED] PR head `a42d9c5761d73ff5d85a4ed84996cddbac16c173` passed the standard repository CI:

- workflow `CI`
- workflow ID `375308650`
- run ID `37378858911`
- run number `64`
- job `static-windows`
- job ID `111995200269`
- PowerShell 7 parser: success
- ASCII/LF verification: success
- simple secret scan: success
- overall conclusion: success

This handover file is a subsequent documentation-only commit, so the reviewer should check the CI associated with the new head rather than assuming the previous run covers this exact commit.

## 7. Review history

The first Codex review of PR #37 raised two valid documentation issues:

1. the non-exportable machine-key requirement was marked `[CONFIRMED]` although ADR-0007/credential contract still keep the product choice proposed;
2. a design document contained stale status for an earlier workflow run.

[CONFIRMED] Both were corrected. The documents now distinguish executed evidence (`[CONFIRMED]`) from adoption/contract choices (`[PROPOSED]`).

[CONFIRMED] A fresh `@codex review` was requested after the accepted two-VM evidence and documentation corrections. Do not assume its result; read the latest PR #37 review comments when resuming.

## 8. Technical conclusion

[CONFIRMED] On the tested Windows images, a machine-scope CNG ECDH P-256 key using `Microsoft Software Key Storage Provider` with `CngExportPolicies.None` is technically viable for the intended credential-module integration.

[CONFIRMED] Replacing the portable folder on the same machine preserves identity.

[CONFIRMED] Copying that folder to another machine does not transfer usable private identity.

[CONFIRMED] The integrated `Sisqual.Credentials` module works with the non-exportable CNG-backed key.

[PROPOSED] Use CNG as the V1 machine-identity mechanism instead of adding DPAPI in parallel, unless a later required operational gate fails.

## 9. Remaining decisions / validation

The next reviewer/AI should not redo the two-VM viability spike unless there is a concrete reason. Remaining work is:

1. [PENDING] Decide the final product CNG key name. Recommendation: application-controlled and derived from `ServerCode`; never supplied by arbitrary browser input.
2. [PENDING] Define the final CNG key ACL and the Windows identity/identities allowed to open it.
3. [PENDING] Determine whether the default machine-key ACL is sufficient or requires an explicit grant.
4. [V] Validate reopen and credential decryption under the intended real application/operator identity on a SISQUAL target or sandbox Windows server.
5. [PENDING] Reviewer/owner decides whether the successful spike is enough to adopt the CNG candidate and update the relevant contract/ADR/decision record.
6. [PENDING] PR #36 SQLite/provider validation remains separate; retry only when a runner is available and preserve all prior infrastructure evidence.

## 10. What not to do

- Do not repeat the accepted CNG two-VM test just to obtain another green run.
- Do not relabel harness failures or runner starvation as cryptographic/provider failures.
- Do not promote the credential contract or CNG adoption to `[CONFIRMED]` without the required reviewer/owner decision.
- Do not introduce DPAPI as a second V1 identity mechanism without a demonstrated CNG operational blocker.
- Do not place the private key inside the portable folder or serialize private-key bytes into artifacts/logs.
- Do not change `docs/decisions-log.md` or `docs/roadmap.md` unless the reviewer/owner explicitly assigns that work.
- Do not merge PR #36 or PR #37 unless explicitly delegated.

## 11. Resume checklist

When continuing this work:

1. read current `AGENTS.md` and `docs/decisions-log.md`;
2. list open PRs and check whether #36/#37 changed or were merged;
3. read the latest comments/reviews on #37, especially the fresh Codex review request;
4. check CI on the current #37 head;
5. read this handover plus the Phase 1B design and evidence ledger;
6. continue with ACL/application-identity validation or the next owner-approved Phase 1B item rather than repeating solved gates.
