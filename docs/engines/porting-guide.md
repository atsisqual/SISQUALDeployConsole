# Engine porting guide

For anyone who ports an engine (ADR-0008, `runtime/Sisqual.Runtime.EngineHost.psm1`). The reference implementation is `engines/Invoke-DeploymentPreflight.ps1` with `tests/EngineHost/Test-DeploymentPreflight*.ps1`. Every item below cost a failed CI run or a review round; read it before writing code.

## 1. Where the engine lives and what it is called
- The file is `engines/<SourceFileName>`, with the name taken from `ops_Engine.SourceFileName` in the catalog. The engine code does not determine it (the 17 real names follow three patterns).
- PowerShell 7 only. No `Invoke-Expression`, no text from the catalog executed as code, no `-EncodedCommand`.

## 2. What the host gives the engine and what it expects back
- The host starts a launcher; after a `GO` line the **request JSON arrives on standard input**. Read it with `[Console]::In.ReadToEnd()` (UTF-8, at most 1 MiB).
- The **result is written to the file named in `resultPath`**, never to standard output. Standard output and standard error must stay silent (the host captures, scans and may refuse them).
- **End every path with an explicit `exit`**: 0 finished with a result, 1 finished with a failure result, 2 invalid request, 3 precondition not met. The launcher passes that code on; without `exit` the code is undefined.
- The result follows `contracts/engine-result.schema.json`. `mode` is `PREVIEW` or `APPLY`; a read-only engine always reports `PREVIEW`.
- The engine does not call the HTTP layer, another engine, or the network.

## 3. PowerShell 7 traps that already cost us
- `ConvertFrom-Json` turns ISO date strings into `DateTime`. Always use `-DateKind String` for the request and for any file with dates, or an exact date parse will fail on a valid request (this is why `DEPLOYMENT_PREFLIGHT` rejected valid requests for days).
- A command argument is not an expression: `-Name [Environment]::MachineName` passes that text. Use parentheses.
- Inside a script block run by a helper, a variable can be hidden by a parameter of the helper with the same name (`$Action`). Copy values to uniquely named variables first.
- `$?` is false after a non-zero `exit`: test `$LASTEXITCODE` first.
- The engine starts with a **minimal environment** (system folders, `PATH`, `TEMP`, user profile folders, `PSModulePath`). Do not read other environment variables; do not use one as a test hook (use a file next to the engine).
- Use `git add -f` for files under `runtime/`: `.gitignore` ignores that folder and a plain `git add` can stop a command chain without a message.

## 4. Secrets
- Secrets reach the engine only in the request field `secrets`. Never in arguments, environment, files, logs, or the result.
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
