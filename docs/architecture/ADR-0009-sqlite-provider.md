# ADR-0009: SQLite provider and tooling versions by role

**Status:** Accepted (2026-10-06); formalized in this ADR on 2026-10-07.
**Decision owner:** Project owner.

## Context

ADR-0007 requires one read-only SQLite catalog per machine inside the portable package. Phase 1B then evaluated a managed SQLite provider for PowerShell 7, and the Phase 3 runtime catalog adopted that provider in product code.

The repository now has two intentionally different SQLite roles:

1. the managed ADO.NET provider used by the application runtime to open the catalog;
2. the standalone SQLite CLI used by conversion, verification and other tooling.

These roles were previously left as a pending formal architecture decision even after runtime adoption had occurred. They must not be collapsed into one nominal SQLite version merely to make the numbers match.

## Decision

The accepted V1 SQLite dependency set is role-specific:

- managed provider: `Microsoft.Data.Sqlite` 10.0.12;
- native SQLite used by that provider/runtime: **3.53.3**;
- standalone SQLite CLI and tooling: **3.53.4**.

Both SQLite versions are accepted simultaneously because they serve different functions. Runtime/provider validation must continue to check its accepted provider/native versions exactly; tooling remains independently pinned to its accepted CLI version.

Release packaging must keep the two roles explicit. Provider/runtime files and tooling files are covered by the signed package manifest, and the remaining manifest integration work must record the two SQLite roles semantically rather than representing them as one shared version.

No operator or target machine dependency on an installed `dotnet`, NuGet restore, or machine-installed SQLite is introduced. The required provider/native payload and tooling CLI are portable dependencies supplied by the package/tooling process.

## Evidence already in `main`

- `docs/phase1/phase1b-sqlite-provider.md` records that `Microsoft.Data.Sqlite` 10.0.12 / SQLitePCLRaw 2.1.12 loaded native SQLite 3.53.3 on Windows Server 2022 and 2025 from both the original and copied portable folders.
- Phase 1B accepted evidence is under `docs/phase1/evidence/phase1b-sqlite-provider-37392036026/`: run `37392036026`, 9/9 gates PASS on both Windows images, including the copied-folder and locked-restore checks.
- `docs/phase3/sqlite-runtime-adoption.md` records the owner's approval to proceed with the role-specific versions: provider/runtime 3.53.3 and CLI/tooling 3.53.4.
- `runtime/Sisqual.Runtime.Catalog.Core.ps1` pins `Microsoft.Data.Sqlite` 10.0.12 and native SQLite 3.53.3 in the product runtime catalog implementation.
- `docs/phase3/runtime-catalog.md` records accepted product evidence from run `37440720047`: Windows Server 2022 and 2025 both passed the runtime catalog and sidecar-hardening suites while using provider 10.0.12, native SQLite 3.53.3 and separate CLI SQLite 3.53.4.

## Consequences

- Documentation and manifests must describe SQLite by role, not as one project-wide SQLite version.
- A provider/runtime upgrade does not implicitly require the tooling CLI to move to the same SQLite patch version, and the reverse is also true.
- Each role remains independently pinned and verified before use.
- The runtime catalog remains read-only and continues to use the managed provider; conversion and verification tooling may continue to use the standalone CLI where designed.
- Changing either accepted version is an architecture/dependency change that requires explicit review and fresh evidence for the affected role.

## Alternatives considered

| Option | Verdict |
|---|---|
| Force provider/runtime and CLI/tooling to the same SQLite patch version | Rejected: the repository already has validated, role-specific dependencies and no functional requirement for artificial version equality |
| Keep `Microsoft.Data.Sqlite` as a spike-only dependency | Rejected: the runtime catalog already uses it in product code and has accepted Windows evidence |
| Require machine-installed SQLite or `dotnet`/NuGet restore at runtime | Rejected: conflicts with the portable/offline deployment model |

## Reopen conditions

Reopen this ADR if the runtime stops using `Microsoft.Data.Sqlite`, either SQLite role changes version or distribution model, the package can no longer carry and verify the required provider/native files, or a platform/security constraint requires a different provider strategy.
