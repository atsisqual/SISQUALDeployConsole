# AGENTS.md

## Mission

Build a portable local administration console for SISQUAL WFM without changing the production Management Console. V1 reads a read-only configuration catalog (a SQLite file shipped inside the portable package, one per machine), verifies the package integrity locally, previews approved operations, and executes on the local Windows server. There is no central configuration database and no master server (owner decision of 2026-10-05, ADR-0007).

## Status vocabulary

Use these labels in design, code comments, PRs, and reports:

- `[CONFIRMED]` - demonstrated by approved evidence, code, test, or recorded run.
- `[PROPOSED]` - recommended but not yet approved.
- `[PENDING]` - information, decision, or validation still required.
- `[DECIDED]` - decided by the owner and traceable to an owner message or an approved document; the date or the owner's words may follow (`[DECIDED 2026-10-08]`).
- `[CLOSED]` - finished: delivered, answered or retired, with nothing left to do; say what closed it.
- `[V]` - implemented or analysed but still requires the specified real Windows/SISQUAL validation.

Never promote an inference to `[CONFIRMED]`. A decision is recorded as made by the owner only when it can be traced to an owner message or an approved document; otherwise write `[PENDING]` with the supporting evidence and ask (rule accepted by the owner on 2026-10-05).

## Source-of-truth order

When sources disagree, use this order:

1. validated real-server evidence and recorded spike evidence;
2. approved ADRs and explicit project-owner decisions;
3. versioned contracts in `contracts/`;
4. current code in this repository;
5. `atsisqual/SISQUALManagementConsole` as read-only historical/reference evidence;
6. agent inference.

Pin evidence to a commit/blob when practical. Large-file reader failures are not evidence that a file is empty.

## Required workflow

Before work:

1. read this file;
2. read `docs/decisions-log.md`;
3. read the relevant ADR and contract;
4. read the relevant `docs/skills/*/SKILL.md` when one exists;
5. list open PRs;
6. reuse the existing branch/PR for the same work after any timeout;
7. otherwise branch from current `main` and open one PR for the task.

Do not push directly to `main`. Do not merge the PR unless the project owner explicitly delegates that action.

If a task depends on an open PR, branch from that PR's branch and use it as the base (a stacked PR); state the integration order in the PR body. The reviewer merges in that order (rule accepted by the owner on 2026-10-05).

## What an agent may decide without new approval

An agent may make implementation choices that do not change an approved public/operational contract, including:

- add or improve deterministic tests;
- internal refactoring with equivalent behaviour;
- documentation corrections supported by evidence;
- secret-safe logging improvements;
- input validation and clearer error handling;
- small UI changes that do not alter security or workflow semantics;
- static-analysis and CI improvements;
- fixes proven by existing tests and approved contracts.

## What requires human approval

Obtain approval before changing:

- cryptographic algorithms, key ownership, trust bootstrap, or credential-envelope semantics;
- the long-term authority of the catalog (deferred by the owner) and the package integrity model (manifest, signing, seal tool);
- anything that makes the application contact a server or write configuration;
- public REST contracts after approval/versioning;
- engine input/result contracts after approval;
- new runtime dependencies or dependency major versions;
- destructive command semantics;
- IIS, SQL, Windows service, Keycloak, TSplus, or Web Access behaviour that differs from approved reference behaviour;
- compatibility removal or scope expansion;
- production execution or use of real credentials.

## Security rules

Never:

- commit credentials, tokens, private keys, production connection strings, or secret values;
- log decrypted secrets or return them through the REST API;
- execute raw SQL supplied by a browser client;
- use `Invoke-Expression` on external or catalog-sourced input;
- accept unvalidated filesystem paths outside approved roots;
- expose Pode beyond loopback by default;
- execute text stored in the catalog or in any data (for example `ops.Action.SqlCommand` or `ops.ReviewDefinition.CommandText`) as code; engine scripts are local versioned files and are never carried in a catalog;
- modify `atsisqual/SISQUALManagementConsole`;
- claim real Windows/SISQUAL validation without evidence.

All privileged inputs must come from approved local contracts or from the verified catalog and credential package, never directly from arbitrary browser fields.

## Engine contract

[PROPOSED] Local engine modules are independent of Pode and expose preview/apply semantics where the operation is mutable.

A normalized engine result contains at least:

```text
OperationId
EngineCode
InstanceCode
StartedAt
FinishedAt
Status
ChangesPlanned
ChangesApplied
Warnings
Errors
BackupArtifacts
```

The draft machine-readable form is `contracts/engine-result.schema.json` ([PROPOSED], PR #13), aligned with the current `SISQUAL_JOB_RESULT_V1`.

Requirements:

- preview is deterministic where technically possible;
- apply uses the same normalized plan/fingerprint when feasible;
- target ownership is validated before execution;
- destructive work has idempotency expectations and backup/restore evidence;
- output is structured and secret-safe;
- engine code does not depend on the HTTP adapter;
- all PowerShell (engines, tools and tests) targets PowerShell 7 and is parsed with the PowerShell 7 parser (owner decision of 2026-10-05, which removes the earlier Windows PowerShell 5.1 requirement); Windows PowerShell 5.1 is needed only for a script explicitly designated as a 5.1 fallback child process under ADR-0006, and such a script must also parse with 5.1.

## Current architecture constraints

- [CONFIRMED] Portable PowerShell 7.6.6, Pode 2.14.1, SQLite 3.53.4 engine.
- [CONFIRMED] Pode is an adapter only.
- [CONFIRMED] Owner decision of 2026-10-05, recorded in ADR-0007 (Accepted by the owner on 2026-10-05; its credential items 4 and 9 keep their [PROPOSED] label until the credential contract is approved): `_sisqualMANAGEMENT` ceases to exist; configuration is a read-only SQLite catalog, one per machine, inside the portable package; the application writes no database and makes no runtime connection to any server to obtain configuration.
- [CONFIRMED] Same decision: the package carries a manifest with the SHA-256 of every file, signed by the credential tool and verified at startup; updating means replacing the whole folder; the owner may edit the catalog by hand and re-seal it with the seal tool.
- [CONFIRMED] Same decision: credentials are never in the catalog or in the portable folder; a separate credential tool issues a package bound to one machine; there is no permanent master server.
- [CONFIRMED] The conversion, verification, seal and credential tools live under `tools/`, run on demand by a person, are not part of the portable application and use PowerShell 7 (owner decisions of 2026-10-05).
- [PENDING] The long-term authority of the catalog (deferred by the owner), the signature algorithm, the canonical form and the trust bootstrap (`contracts/credential-package.md`, questions Q1 and Q2).
- [CONFIRMED] IIS integration is through `Microsoft.Web.Administration` under PowerShell 7, subject to ADR-0006 conditions.
- [CONFIRMED] Process lifetime is interactive only; no service or scheduled task.
- [PENDING] Managed SQLite provider (it only has to open a file read-only) and machine-key implementation are Phase 1B decisions.
- [PENDING] Local web security and controlled shutdown are Phase 1C decisions.

## Completion checklist for every PR

- scope matches one task;
- evidence labels are correct;
- no secrets added;
- ASCII and LF for changed text files unless an approved evidence file requires otherwise;
- the PowerShell 7 parser check passes for changed `.ps1` files (and the 5.1 parser for a designated 5.1 fallback script);
- tests and docs updated together when behaviour changes;
- remaining `[PENDING]` and `[V]` items are stated in the PR body.
