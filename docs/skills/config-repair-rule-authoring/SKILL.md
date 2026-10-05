# Skill: config-repair-rule-authoring

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Guide creation or review of central configuration-repair rules without writing them back from SISQUALDeployConsole V1.

## Required inputs

- target application/config file;
- current file format and selector semantics;
- desired value/template and validation type;
- evidence from existing `cfg.ConfigRule` / `cfg.ConfigFile` behaviour.

## Safety rules

- V1 produces rule proposals only; it does not author central configuration.
- Never use raw browser-supplied scripts or unvalidated regex/selector content as executable code.
- Require deterministic match-count/precondition checks for text replacements.
- Preserve file encoding and validate post-repair semantics.

## Expected outputs

- proposed central rule fields;
- preview examples against synthetic fixtures;
- validation/precondition expectations;
- generated SQL/text for separate human-controlled central authoring if requested;
- `[PENDING]` and `[V]` items.

## Dependencies

[PENDING] Final workflow depends on the ported CONFIG_REPAIR engine and approved central snapshot contract.
