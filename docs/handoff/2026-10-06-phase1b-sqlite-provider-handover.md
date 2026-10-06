# Phase 1B SQLite provider handover

**Date:** 2026-10-06
**PR:** #36 `spike/phase1b-sqlite-managed-provider`
**Status:** [CONFIRMED] technical viability proved; [PROPOSED] product adoption; no merge performed by this handover.

## 1. Resume point

The managed SQLite provider spike is technically complete. Do not restart provider selection unless the owner/reviewer rejects the candidate or the native-version packaging decision requires a different payload.

Accepted candidate:

- `Microsoft.Data.Sqlite` 10.0.12;
- SQLitePCLRaw 2.1.12 dependency closure;
- portable PowerShell 7.6.6;
- read-only catalog connection mode.

Accepted evidence directory:

`docs/phase1/evidence/phase1b-sqlite-provider-37392036026/`

## 2. Accepted run

- workflow `phase1b-sqlite-provider`;
- workflow ID `375792558`;
- run ID `37392036026`;
- run number `5`;
- attempt `1`;
- commit `71e1151b6747b1ceee9e5529db1d40d0759fcdad`;
- conclusion `success`.

Windows 2022:

- job `112039131637`;
- runner `GitHub Actions 1000000658` / runner ID `1000000658`;
- artifact `11381318431`;
- artifact digest `sha256:d436a7eadcfb728f9cbc446c333aef7fa3475e663ccd294c0c4d4b6450d90020`.

Windows 2025:

- job `112039131900`;
- runner `GitHub Actions 1000000659` / runner ID `1000000659`;
- artifact `11382140601`;
- artifact digest `sha256:03f0a0ce92ed90d0634977dba284226f6db15c69d39c1c6dfd351b558097405d`.

Both artifacts were downloaded and inspected. Original and copied provider folders each passed 9/9 gates with `fatalError=null`.

## 3. What is [CONFIRMED]

- provider loads directly from copied files without installation;
- exact PowerShell 7.6.6 host;
- parameterized read-only queries work;
- `PRAGMA integrity_check` returns `ok`;
- INSERT is rejected;
- missing database is not created;
- 20 simultaneous read-only connections work;
- catalog bytes are unchanged;
- no sidecar file is created;
- copied provider folder behaves identically;
- NuGet locked restore succeeds from an empty cache;
- exact six-package graph and raw archive hashes are recorded identically on Windows 2022 and 2025.

## 4. Exact dependency hashes

- `Microsoft.Data.Sqlite` 10.0.12: `246679D8C6C83FFCF4C8A480066E3F4FC4E051C96B71BEDFD932FE7A5AF1F7D4`
- `Microsoft.Data.Sqlite.Core` 10.0.12: `5E8ED353006DADF55D5C7F56D237321C20BB10C786262E6B25526756E1036332`
- `SQLitePCLRaw.bundle_e_sqlite3` 2.1.12: `A9A06E6B5A313F6EF3675F91997D012ADEFFE8AA9E1FFD69ED46A4E685B054E1`
- `SQLitePCLRaw.core` 2.1.12: `AF06904138FFA6DC95A599133D64D254716D6FACC7543A6B3B910793DAE9DCA5`
- `SQLitePCLRaw.lib.e_sqlite3` 2.1.12: `4A22C02FFCF489792903CF263DEF9FCE27739716883F965F0B5EEFF1637430AC`
- `SQLitePCLRaw.provider.e_sqlite3` 2.1.12: `DF2B3271992E5D719186C4671E3CF4F8658097C154CBCD41494AB594C5997595`

`packages.lock.json` SHA-256: artifact bytes `F0C6BAD7D4581F55ED79E0182429E89BE888E62AC6684E88D0D05095278948EA` (2206 bytes); committed bytes in Git (LF) `C380C7EC969189221C8B521B5218F7426B1ED03F519F6FCBCDAF3D0ABA35CAD4` (2148 bytes).

`nuget-graph.json` SHA-256: artifact bytes `2F78A1CA873E2EA70901F4C67420847420C7B9CA7AF7CBB3B24C0F56DCE1A3C7` (3567 bytes); committed bytes in Git (LF) `D0035D1A2640EB72C56A4038A60C536088D2367154D78A517C70BB3CFEF27F65` (3505 bytes).

Verify the Git copy with the committed hashes; the artifact hashes apply to the files inside the workflow artifacts.

## 5. Important packaging decision still open

[CONFIRMED] The candidate provider loads native SQLite `3.53.3`.

[CONFIRMED] The repository's separate SQLite CLI is `3.53.4`.

[PENDING] The owner/reviewer must either:

- accept two explicit pinned patch versions by role; or
- require the provider/native runtime to be aligned to 3.53.4 and rerun the spike.

Recommendation: accept the tested provider payload unless support/security policy requires alignment. If accepted, both versions must be explicit in the package manifest so there is no hidden runtime version.

## 6. Historical failures - do not erase

### Run `37370494285` - run #1

- attempt 1 jobs `111966131168` / `111966131543`: no runner, zero steps;
- attempt 2 jobs `111971823366` / `111971823059`: no runner, zero steps;
- infrastructure evidence only.

### Run `37372704803` - run #2

Attempt 1:

- jobs `111973546139` / `111973546324`;
- no runner, zero steps.

Attempt 2:

- windows-2022 job `112035154375`, runner ID `1000000644`, artifact `11381246946`, digest `sha256:afaab5d7c7e1838ec4576e2c6c45ea590e76c96a540748a4199ae1e450562b9d`;
- windows-2025 job `112035154659`, runner ID `1000000643`, artifact `11380983142`, digest `sha256:7b8b5216a10dc7851d5b7675b4779d4d0ffb65838bc41e7186b6399851c34e6c`;
- failed because of probe/evidence harness defects, not because read-only provider behavior failed.

### Run `37391452873` - run #3

- commit `6fa275a180d48271cdc2e98dff86f638e805bded`;
- windows-2022 job `112037270909`, runner ID `1000000650`, artifact `11382045245`, digest `sha256:4f2ebdaa0b4d7eddd20d8a13374b314d98287f8dbc51e8e9ddfe1bffaf87be32`;
- windows-2025 job `112037270985`, runner ID `1000000651`, artifact `11381620840`, digest `sha256:cac22fa860fd795a1201d1c21754863aac734d65b3763f206bf59babe6b84c06`;
- original and copied provider probes passed; dependency-evidence/summary logic failed.

### Run `37391503600` - run #4

- commit `044c7502f1490d770561151b29e3f860e7b09c0e`;
- windows-2022 job `112037433930`, runner ID `1000000653`, artifact `11381530977`, digest `sha256:ff1fb2cead35fbcfa7692228b8b38e06cb2d820dcc1a0a20a251fa0210b9783f`;
- windows-2025 job `112037434118`, runner ID `1000000654`, artifact `11381202949`, digest `sha256:a8b5355bed7a3bba6b94ffdc28342f0499135b9d2da9e103ac4c9433d9de7246`;
- original and copied provider probes passed; only the manual NuGet content-hash comparison failed.

### Run `37392036026` - run #5

First fully accepted run. See section 2 and the evidence directory.

## 7. What not to do

- do not call runs #2-#4 provider failures; their provider probes either progressed successfully or passed, while harness/evidence logic failed;
- do not compare raw `.nupkg` SHA-512 directly with NuGet lock `contentHash`;
- do not add `dotnet` as an operator-machine runtime requirement;
- do not add the provider to the product package before dependency approval;
- do not hide the native SQLite 3.53.3 version behind the separate 3.53.4 CLI pin;
- do not repeat the two-OS spike unless the provider payload changes.

## 8. Remaining work

[PENDING] Owner/reviewer approval to adopt the runtime dependency.

[PENDING] Native SQLite version policy (3.53.3 provider versus 3.53.4 CLI).

[V] Read-only open of one converted SISQUAL catalog on a target/sandbox Windows machine.

After approval, Phase 3 can use this evidence to implement the real read-only catalog factory and startup verification.
