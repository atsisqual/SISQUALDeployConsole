# Skill: bootstrap-new-server

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Guide an operator through preparing a new Windows server for SISQUALDeployConsole and SISQUAL WFM without performing central configuration writes in V1.

## Required inputs

- target machine identity;
- approved central snapshot/source information;
- expected SISQUAL roots and prerequisites;
- intended environment/instance scope.

## Safety rules

- Never write central `_sisqualMANAGEMENT` configuration.
- Never create or store real credentials in the repository.
- Preview every proposed machine change before execution.
- Stop when a prerequisite or ownership check is ambiguous.

## Expected outputs

- prerequisite report;
- machine identity/public-key information when Phase 1B is approved;
- required central configuration as generated SQL/text for a human to apply separately;
- validation checklist and `[V]` items.

## Dependencies

[PENDING] Final workflow depends on Phase 1B, central sync, credential packages, and mature engine modules.
