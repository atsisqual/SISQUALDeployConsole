# Skill: rename-instance

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Plan and validate an instance-code rename across all known dependent surfaces.

## Required inputs

- current InstanceCode;
- proposed InstanceCode;
- dependency inventory taken from the catalog of the machine (an instance belongs to exactly one machine);
- target server identity.

## Known dependency examples

[CONFIRMED] Phase 0 identified dependencies including `sec.ManagedCredential`, `cfg.LinksPageInstanceApplication`, and `ops.PulseCheckState`, plus newer related surfaces that must be discovered before execution.

## Safety rules

- V1 does not edit the catalog: a rename is planned here and applied by the owner to the catalog, which is then sealed.
- Never assume `dbo.ManagedInstance` is the only dependency.
- Produce a complete dependency preview before any local/target-system mutation.
- Abort on unresolved foreign-key or semantic references.

## Expected outputs

- dependency map;
- previewed rename plan;
- catalog changes the owner must apply and seal;
- local/target changes, if an approved engine supports them;
- `[PENDING]` and `[V]` validation items.

## Dependencies

[PENDING] Final workflow depends on approved engine ports and the approved catalog contract.
