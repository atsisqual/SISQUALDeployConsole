# SQLite runtime adoption approval

**Date:** 2026-10-06
**Status:** [CONFIRMED]

The project owner explicitly instructed the reviewer to validate the current work and proceed (`Valida e avanca`). This instruction followed the Phase 1B validation and the recommendation to keep the two SQLite patch versions explicit by role.

The approved V1 integration is:

- `Microsoft.Data.Sqlite` 10.0.12 for the managed ADO.NET provider;
- native SQLite 3.53.3 carried by that provider;
- separate SQLite CLI/tooling 3.53.4;
- both roles remain explicit in packaging/manifest integration rather than being collapsed into a single SQLite version;
- no `dotnet` or NuGet restore is introduced as an operator/runtime dependency.

This record formalizes the owner preference that was still marked `[PENDING formalisation]` in `docs/decisions-log.md` at the base of PR #54. It is the approval basis for the runtime dependency used by PR #54.

Reference evidence for the provider itself remains Phase 1B run `37392036026`; product integration evidence is recorded under `docs/phase3/evidence/`.
