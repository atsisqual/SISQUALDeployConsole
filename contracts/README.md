# Contracts

**Status:** [PROPOSED] draft. Nothing in this folder is approved. Versioned as `0.1-proposed`.
Tags: [CONFIRMED] confirmed by evidence or owner decision; [PROPOSED] draft for review; [PENDING] open decision; [V] only verifiable on a real server.

## Index

| File | What it defines | Replaces or relates to |
|---|---|---|
| `package-manifest.schema.json` | Signed manifest of the portable package: SHA-256 of every file and the catalog identity | Replaces the planned `sync-manifest.schema.json` (see below) |
| `catalog-schema.md` | Rules and metadata of the per-machine read-only SQLite catalog | Table list is [PENDING] the conversion plan (`docs/migration/catalog-conversion-plan.md`) |
| `engine-result.schema.json` | Structured result every engine returns | Aligned with the current `SISQUAL_JOB_RESULT_V1` and the `Add-Result` rows |
| `credential-package.md` | Envelope of the machine-bound credential package issued by the separate credential tool | Owner decision of 2026-10-05 |
| `api/openapi.yaml` | Skeleton of the loopback REST API | No sync endpoints (there is no sync) |

## Why there is no sync contract

[CONFIRMED] Owner decision of 2026-10-05: there is no master server and `_sisqualMANAGEMENT` ceases to exist; the application never contacts a server to obtain configuration (ADR-0007, proposed). The planned sync manifest is therefore replaced by two things: the signed package manifest (hashes of all files) and the per-machine catalog schema.

## Rules for every contract here

- ASCII only, LF line endings.
- Examples use invented values (`EXAMPLE_SERVER`, all-zero hashes). No real server names, no credentials, no keys.
- A contract changes only through a PR that bumps its version and records the owner approval.
- Secrets never appear in any document defined here, except as ciphertext inside a credential package.
- Unknown fields are rejected (`additionalProperties: false`) unless a contract says otherwise.
