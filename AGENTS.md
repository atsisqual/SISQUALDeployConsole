# AGENTS.md

## Mission

Build a portable local administration console for SISQUAL WFM without changing the production Management Console. V1 reads central configuration, validates it locally, previews approved operations, and executes on the local Windows server.

## Status vocabulary

Use these labels in design, code comments, PRs, and reports:

- `[CONFIRMED]` - demonstrated by approved evidence, code, test, or recorded run.
- `[PROPOSED]` - recommended but not yet approved.
- `[PENDING]` - information, decision, or validation still required.
- `[V]` - implemented or analysed but still requires the specified real Windows/SISQUAL validation.

Never promote an inference to `[CONFIRMED]`.

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
- central-authority versus local-cache ownership;
- sync transport or snapshot authority rules;
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
- use `Invoke-Expression` on external or synchronized input;
- accept unvalidated filesystem paths outside approved roots;
- expose Pode beyond loopback by default;
- let central `ops.Engine.ScriptText` replace local executable modules at runtime;
- modify `atsisqual/SISQUALManagementConsole`;
- claim real Windows/SISQUAL validation without evidence.

All privileged inputs must come from approved local contracts or validated central snapshot data, never directly from arbitrary browser fields.

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

Requirements:

- preview is deterministic where technically possible;
- apply uses the same normalized plan/fingerprint when feasible;
- target ownership is validated before execution;
- destructive work has idempotency expectations and backup/restore evidence;
- output is structured and secret-safe;
- engine code does not depend on the HTTP adapter;
- PowerShell scripts must parse with Windows PowerShell 5.1 until that compatibility requirement is explicitly removed.

## Current architecture constraints

- [CONFIRMED] Portable PowerShell 7.6.6, Pode 2.14.1, SQLite 3.53.4 engine.
- [CONFIRMED] Pode is an adapter only.
- [CONFIRMED] Central `_sisqualMANAGEMENT` is authoritative and V1 is read-only toward central configuration.
- [CONFIRMED] IIS integration is through `Microsoft.Web.Administration` under PowerShell 7, subject to ADR-0006 conditions.
- [CONFIRMED] Process lifetime is interactive only; no service or scheduled task.
- [PENDING] Managed SQLite provider and machine-key implementation are Phase 1B decisions.
- [PENDING] Local web security and controlled shutdown are Phase 1C decisions.

## Completion checklist for every PR

- scope matches one task;
- evidence labels are correct;
- no secrets added;
- ASCII and LF for changed text files unless an approved evidence file requires otherwise;
- PowerShell 5.1 parser check passes for changed `.ps1` files;
- tests and docs updated together when behaviour changes;
- remaining `[PENDING]` and `[V]` items are stated in the PR body.
