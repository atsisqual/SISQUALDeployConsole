# Skill: config-repair-rule-authoring

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Guide creation or review of configuration-repair rules (the `cfg_ConfigRule` rows of the catalog) without the application writing them in V1.

## Required inputs

- target application/config file;
- current file format and selector semantics;
- desired value/template and validation type;
- evidence from existing `cfg.ConfigRule` / `cfg.ConfigFile` behaviour.

## Safety rules

- V1 produces rule proposals only; it does not write the catalog (the owner edits and seals it).
- [PROPOSED] A rule template never contains a literal secret; it holds a reference to the credential package (the conversion tool replaces literal secrets by `{{secret:RULE:<RuleCode>}}`).
- Never use raw browser-supplied scripts or unvalidated regex/selector content as executable code.
- Require deterministic match-count/precondition checks for text replacements.
- Preserve file encoding and validate post-repair semantics.

## Expected outputs

- proposed rule fields;
- preview examples against synthetic fixtures;
- validation/precondition expectations;
- text for the owner to apply to the catalog and seal, if requested;
- `[PENDING]` and `[V]` items.

## Dependencies

[PENDING] Final workflow depends on the ported CONFIG_REPAIR engine and approved catalog contract (`contracts/catalog-schema.md`).
