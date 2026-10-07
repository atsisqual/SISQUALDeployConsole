# ADR-0008: Engine host contract

**Status:** Accepted (2026-10-07). The owner accepted the decision and the six recommendations at the end ("Aceito tudo", 2026-10-07).
**Relates to:** ADR-0001 (runtime), ADR-0007 (catalog, logs, no state database), `contracts/engine-result.schema.json`, `docs/phase1/phase1c-operation-coordinator.md` (locks and idempotency), `AGENTS.md` ("Engine contract").

## Context

The runtime can start, verify the manifest, open the catalog read-only and write logs. The 17 engine specifications in `docs/engines/` say what each engine does. Nothing yet says how an engine is found, started, limited, locked, logged and checked, so every engine port would invent its own answer. This ADR fixes that once, before wave 1.

Facts from the source snapshot (`ManagementSync.sql`, nightly of 2026-10-07):

- `ops.Action` has 24 rows: 18 of type `ENGINE`, 3 `COMPOSITE` (`CLEANUP_RETIRED_OBJECTS`, `CREDENTIAL_TEST`, `FULL_DEPLOYMENT`) and 3 `SQL` (`EXECUTION_HISTORY`, `LINKS_VISIBILITY_MATRIX`, `OBJECT_AUDIT`).
- `ModePolicy` is `NONE` (6 actions) or `PREVIEW_APPLY` (18). `InstanceSelectionPolicy` is `NONE` or `ALL_ENABLED`. `CommandTimeoutSeconds` is 0, 120, 300 or 900.
- The two wave 1 engines: `DEPLOYMENT_PREFLIGHT` is `NONE`, all instances, receives the instance code, timeout 0; `PULSE_STATUS` is `PREVIEW_APPLY`, no instance selection, receives the apply flag, timeout 900.
- The catalog does not carry `ops.Engine.ScriptText` or `ScriptSha256` (the converter excludes them). An engine is therefore a local file, never text from the catalog (`AGENTS.md`: never execute text stored in the catalog).
- `engine-result.schema.json` accepts `mode` `PREVIEW` or `APPLY` only.

## Decision

1. **Engines are local files.** `engines/Invoke-<EngineCode>.ps1`, written for PowerShell 7. `ops_Engine.SourceFileName` must equal that file name, and the file must be listed in the signed manifest. The host verifies its SHA-256 against the manifest immediately before every launch, not only at startup.
2. **One child process per run.** The host starts `pwsh -NoProfile -NonInteractive -File <engine>` with a fixed command line that contains no secret and no data. The request is read from **standard input** as UTF-8 JSON without BOM (at most 1 MiB). The result is written to a **result file** in a folder the host creates for that run, readable only by the current user and deleted afterwards. Standard output carries progress lines only (captured, redacted, capped at 1 MiB).
3. **Request** (host to engine): `contractVersion`, `operationId`, `engineCode`, `mode` (`PREVIEW` or `APPLY`), `instanceCode` (or null), `catalogPath` (read-only), `planFingerprint` (only for `APPLY`), `deadlineUtc`, `cancelPath`, `resultPath`, and `secrets`, a map from `credentialRef` to value limited to the references the engine specification declares. Secrets exist only in this request.
4. **Exit codes.** 0 the engine finished and wrote a result; 1 it finished with a failure result; 2 invalid request; 3 a precondition is not met (version, elevation). Anything else, or no valid result, makes the host synthesise a failure result `ENGINE_NO_RESULT`. The `succeeded` field of the result decides success, not the exit code alone.
5. **Result.** Validated against `contracts/engine-result.schema.json` (at most 4 MiB). `operationId`, `engineCode` and `mode` must echo the request, and `summary` counts must equal what `results` contains. An invalid result becomes a synthesised failure and the invalid file is not shown.
6. **Modes and plans.** `PREVIEW` never changes anything and returns `planFingerprint`: the SHA-256 of the canonical JSON of the plan (sorted keys, the canonical form of `Seal-Package`). `APPLY` receives that fingerprint, recomputes the plan, and refuses with `PLAN_CHANGED` if it differs. For `PREVIEW_APPLY` actions the host requires a `PREVIEW` in the same host session before an `APPLY` (memory only, ADR-0007: a restart means preview again). Read-only engines (`ModePolicy` `NONE`) always run as `PREVIEW`.
7. **Actions.** The host enforces `ops_Action`: `ENGINE` starts the engine; `COMPOSITE` runs its `ops_ActionStep` children in `StepOrder` through the same host (an engine never calls another engine); `SQL` is refused with `ACTION_TYPE_NOT_SUPPORTED` because the host never executes catalog text. `RequiresInstanceSelection`, `AllowAllInstances`, `InstanceSelectionPolicy`, `PassInstanceCode` and `PassApply` decide what the request contains, and `APPLY` needs the caller to echo `ConfirmationText`.
8. **Preconditions checked by the host before launch:** the engine row `IsEnabled`, `MinimumPowerShell` not above the running version, `RequiresAdministrator` against the current elevation, and the catalog machine (`dbo_ManagedServer.MachineName`) equal to the local computer name, ignoring case. Engine-specific preflight stays in the engine.
9. **Concurrency and idempotency** use the operation coordinator of phase 1C: `INSTANCE:<InstanceCode>` locks for instance runs, plus the shared locks the engine specification declares and a `MACHINE` lock for machine-wide effects; `LOCK_CONFLICT` and `IDEMPOTENCY_CONFLICT` as in that ADR. The request fingerprint already includes the mode.
10. **Timeout and cancellation are cooperative.** The host writes `cancelPath` and the engine checks it between steps. On timeout the host asks for cancellation and waits a grace period (30 s). A read-only engine is then killed with its process tree. A mutable engine is **not** killed: the operation becomes `TIMED_OUT_RUNNING`, the lock stays held, and only an explicit operator action ends it (phase 1C: a running destructive operation is not safely cancellable by inference).
11. **Secret safety, checked by the host.** After every run the host scans the result file, the captured output and its own log lines for each secret value it passed, and for its base64 and URL-encoded forms. A hit discards the result, fails the operation with `SECRET_LEAK`, and logs only the reference, never the value. Engines never put a secret in an argument, environment variable, file or log line.
12. **Logging** through `Sisqual.Runtime.Logging`: operation id, engine, mode, instance, locks, plan fingerprint, duration, exit code and result summary. Never a value.
13. **Conformance kit** in `tests/EngineHost/`, run for every engine on Windows CI: schema-valid result; `PREVIEW` changes nothing (a file-system hash before and after); `APPLY` twice reports no changes the second time; a canary secret never appears in the result, output, arguments or environment; cancellation is respected; timeout behaves as in item 10; an invalid request exits 2; a stale fingerprint is refused.

## Alternatives considered

- **In-process runspace.** Faster to start, but there is no hard timeout, a hang or crash takes the console down, secrets share the web process memory, and `Microsoft.Web.Administration` would be loaded into it. Rejected.
- **Dot-sourced functions.** Same problems and no isolation. Rejected.
- **Secrets through a named pipe or callback.** Stronger against a same-user process reading the pipe, but heavier. Standard input is not visible in the process list or the environment; revisit only if a threat review asks for more.

## Consequences

- The first engine port can be tested end to end with a small fake engine before any real one exists.
- Wave 1 is read-only, so it exercises items 1 to 6, 8, 11 and 12 without the destructive parts (10 for mutable engines is proven with a test engine).
- Not decided here: the web layer that triggers operations, the shared lock names of each engine (they belong in each engine specification), and the order of `FULL_DEPLOYMENT` steps (wave 6).

## Questions answered by the owner (2026-10-07, "Aceito tudo")

1. [DECIDED 2026-10-07] One child process per run (above), not an in-process runspace. Recommendation: child process.
2. [DECIDED 2026-10-07] Read-only engines report `mode` `PREVIEW`, with no change to the result schema, rather than a new `READ_ONLY` value. Recommendation: `PREVIEW`.
3. [DECIDED 2026-10-07] The three `SQL` actions are refused. `EXECUTION_HISTORY` is replaced by reading the text logs, `LINKS_VISIBILITY_MATRIX` by the read-only matrix of wave 8, and `OBJECT_AUDIT` needs a decision: an engine or retire. Recommendation: decide `OBJECT_AUDIT` when its wave is planned; the host refuses it until then.
4. [DECIDED 2026-10-07] When `CommandTimeoutSeconds` is 0 the host applies 900 seconds; an engine that needs longer sets it in the catalog. Recommendation: accept.
5. [DECIDED 2026-10-07] The console runs elevated only if an enabled engine requires administrator; otherwise those engines are listed as unavailable. [V] Check on a real server.
6. [DECIDED 2026-10-07] A mutable engine that times out is never killed by the host (item 10). Recommendation: accept.
