# Skill: bootstrap-new-server

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Guide an operator through preparing a new Windows server for SISQUALDeployConsole and SISQUAL WFM without the application writing any configuration in V1 (the catalog is read-only).

## Required inputs

- target machine identity;
- the catalog and manifest of the target ServerCode; for a machine that is not in the old system, a catalog produced by the conversion tool in new-machine mode;
- expected SISQUAL roots and prerequisites;
- intended environment/instance scope.

## Safety rules

- Never write to the catalog from the application; the owner edits the catalog by hand and seals it (ADR-0007, item 7).
- Never create or store real credentials in the repository.
- Preview every proposed machine change before execution.
- Stop when a prerequisite or ownership check is ambiguous.

## Expected outputs

- prerequisite report;
- machine identity/public-key information when Phase 1B is approved;
- required catalog changes as text for the owner to apply to the catalog and seal;
- validation checklist and `[V]` items.

## Dependencies

[PENDING] Final workflow depends on Phase 1B, the per-machine catalog and its integrity check, the credential tool, and mature engine modules.
