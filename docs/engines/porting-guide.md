# Engine porting guide

For anyone who ports an engine (ADR-0008, `runtime/Sisqual.Runtime.EngineHost.psm1`). The reference implementation is `engines/Invoke-DeploymentPreflight.ps1` with `tests/EngineHost/Test-DeploymentPreflight*.ps1`. Every item below cost a failed CI run or a review round; read it before writing code.

## 1. Where the engine lives and what it is called
- The file is `engines/<SourceFileName>`, with the name taken from `ops_Engine.SourceFileName` in the catalog. The engine code does not determine it (the 17 real names follow three patterns).
- PowerShell 7 only. No `Invoke-Expression`, no text from the catalog executed as code, no `-EncodedCommand`.

## 2. What the host gives the engine and what it expects back
- The host starts a launcher; after a `GO` line the **request JSON arrives on standard input**. Read it with `[Console]::In.ReadToEnd()` (UTF-8, at most 1 MiB).
- The **result is written to the file named in `resultPath`**, never to standard output. Standard error must stay silent. Standard output may carry non-secret progress lines (ADR-0008 item 2) up to the host's size limit; the host captures both streams and scans them for every secret it passed, and refuses a stream that exceeds the limit or leaks one.
- **End every path with an explicit `exit`**: 0 finished with a result, 1 finished with a failure result, 2 invalid request, 3 precondition not met. The launcher passes that code on; without `exit` the code is undefined.
- **Plan fingerprint (every engine whose action is `PREVIEW_APPLY`).** The schema marks `planFingerprint` optional, but the host refuses a preview result without a valid one (64 lowercase hex characters) as `ENGINE_INVALID_RESULT`, and refuses an `APPLY` that does not carry the fingerprint of an earlier preview of the same plan. The engine must recompute the plan on `APPLY` and stop with exit 3 if it no longer matches (drift). A `READ_ONLY` engine has no apply and no fingerprint requirement.
- The result follows `contracts/engine-result.schema.json`. `mode` is `PREVIEW` or `APPLY`; a read-only engine always reports `PREVIEW`.
- The engine does not call the HTTP layer or another engine. It uses the network only where its specification approves it (for example HTTPS health checks for `PULSE_STATUS`, loopback calls for `WEB_ACCESS`, local SQL connections). Anything the specification does not name is not allowed.

## 3. PowerShell 7 traps that already cost us
- `ConvertFrom-Json` turns ISO date strings into `DateTime`. Always use `-DateKind String` for the request and for any file with dates, or an exact date parse will fail on a valid request (this is why `DEPLOYMENT_PREFLIGHT` rejected valid requests for days).
- A command argument is not an expression: `-Name [Environment]::MachineName` passes that text. Use parentheses.
- Inside a script block run by a helper, a variable can be hidden by a parameter of the helper with the same name (`$Action`). Copy values to uniquely named variables first.
- `$?` is false after a non-zero `exit`: test `$LASTEXITCODE` first.
- The engine starts with a **minimal environment** (system folders, `PATH`, `TEMP`, user profile folders, `PSModulePath`). Do not read other environment variables; do not use one as a test hook (use a file next to the engine).
- `runtime/` is tracked source code (owner decision of 2026-10-09, PR #73): a plain `git add` works, and only `runtime/sqlite-provider/` (the materialized provider binaries) is ignored. Whatever you add, check with `git status` that the file is staged before you commit: a chain `git add && git commit` stops without a message if the add fails.

## 4. Secrets
- Secrets reach the engine only in the request field `secrets`. Never in arguments, environment, logs, or the result, and never written to a file except the managed target that the engine's specification explicitly approves (for example the repaired application configuration of `CONFIG_REPAIR`, the machine-protected credential file of `WEB_ACCESS`, or the database row that `KEYCLOAK_CLIENT_SECRETS` updates).
- Declare the references the engine reads in `contracts/engine-secret-references.json`, in the same PR, as exact references or per kind (`IIS_IDENTITY.*`, `WEB_ACCESS.*`, `MOBILE_APP_TOKEN.*`, `RULE_SECRET.*`). Declare only what the specification says the engine needs. An engine that reads a credential its specification does not mention is a defect, not a convenience.
- The host scans the result, standard output and standard error for every secret value it passed (plain, base64, URL and form encodings). Test with canary values that are long and unique (a one-character value is found everywhere).

## 5. The tests every engine needs
- A conformance test that runs the engine through the host on Windows, a mutation test that fails without each piece of engine code, and one test per issue code of the specification.
- `PREVIEW` must not change the managed system (file-system hash before and after).
- Classes: `READ_ONLY` only if every action that uses the engine has `ModePolicy` `NONE`; `MUTATING` if it can change the system; `OBSERVATIONAL` only for measurement. When in doubt, `MUTATING`. The host kills a timed-out engine only when its action cannot apply.
- Synthetic fixtures only, no real value. The host tests do not need a real server; the real-catalog proof is run by the reviewer on the converted catalogs.
- Windows-only code (job objects, processes, ACLs) can only be verified in CI. Make the test fail before you trust it.

## 6. Working method (read this; it is why earlier attempts timed out)
- One small step per commit, one push per commit. Never wait for CI inside the same turn: end the turn, read the result in the next one.
- CI logs are not readable through the API. The workflows publish them to `results/<workflow>-<run>-<attempt>-<os>`; read them there. **Do not create `proof/*` branches or driver workflows.**
- End every turn saying exactly what is pushed (head sha), what is only local, and what is missing. Distinguish "I verified now" from "it was in CI".
- Ask for `@codex review` once, for the final head. Confirm open threads with GraphQL `isResolved` **after** the review. A review that finds something at a new head is normal: fix it with a test and ask again.
- Do not merge. Do not change `runtime/`, `contracts/`, ADRs or `.github/` except what the task names. Anything that changes what an engine receives or sees needs the owner's approval first (`AGENTS.md`).
