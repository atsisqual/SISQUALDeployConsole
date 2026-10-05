# ADR-0007: Embedded read-only catalog, no runtime sync, text logs

**Status:** Proposed (2026-10-05). Direction given by the project owner in conversation; needs explicit approval before it becomes Accepted.
**Supersedes in part:** ADR-0001 (SQLite as a local cache synchronised from the central database) and the decision of 2026-10-05 "central sync transport: direct read-only SQL" (there is no central database to read from any more; a one-time migration tool reads `_sisqualMANAGEMENT` read-only to produce the initial catalog source). The planned ADR on the central sync model is replaced by this one.

## Context

The owner does not want a master server, and `_sisqualMANAGEMENT` ceases to exist (the SQL Server databases of the managed instances remain). Updating means replacing the whole portable folder. The database must be read-only. Logs must be plain text in a configurable folder.

## Decision

1. **Catalog.** The configuration catalog is a SQLite file shipped inside the portable. The application opens it read-only and never writes to it. [PROPOSED] Its authority is declarative source files in this repository (format [PENDING]: JSON or SQL seed), changed only through reviewed pull requests; a build tool compiles them into the catalog. A one-time migration tool reads `_sisqualMANAGEMENT` read-only to produce the initial source; after the cutover that database is decommissioned. Secret-bearing data never enters the catalog or the repository (R-026).
2. **Updates.** The whole portable folder is replaced (catalog, engines, UI). The application makes no runtime connection to SQL Server or to any remote server to obtain configuration.
3. **Integrity.** The package carries a manifest with the SHA-256 of every file, including the catalog, verified at startup. The UI shows the catalog source, build time and schema version, because a stale catalog is now the main risk. [PENDING] whether the manifest is also signed by the credential tool key.
4. **Credentials [PROPOSED].** Stored in a separate SQLite file outside the portable folder, by default `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\credentials.db`, read-only at runtime, produced by the separate credential tool, which needs a source for the secrets once `_sisqualMANAGEMENT` is gone ([PENDING], see open items). Values are encrypted for the machine (content key wrapped with the machine public key, package signed by the tool), decrypted only in memory when needed and never logged. The private key is the non-exportable machine key created on the machine (Phase 1B) and also lives outside the portable folder, so replacing the portable keeps it. Rejected alternative: credentials inside the portable catalog, which needs one build per machine on every release.
5. **Local state.** The application writes no database. Operation history goes to the text logs; locks and idempotency tokens are kept in memory (V1 has a single operator).
6. **Logs.** Plain text files in a configurable folder, default `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement\`. They never contain secrets or tokens (R-008). [PROPOSED] one file per day, kept 30 days, both configurable.

## Consequences

- The snapshot sync phase and its failure modes disappear (R-002, R-003, R-036 mostly); new risk: a stale catalog is used without anyone noticing.
- The one-off migration tool, the catalog build tool and the credential tool are separate tools under `tools/`, run on demand by a person, and are not part of the portable application.
- WAL and concurrent writers are no longer needed. The SQLite provider only has to open a file read-only.
- The roadmap changes: the sync phase is replaced by the catalog build tool and the one-time migration, the credential package work becomes the credential tool, and the coexistence plan with the current Management Console becomes a cutover and decommission plan.

## Alternatives considered

| Option | Verdict |
|---|---|
| Local cache synchronised from a central database (ADR-0001) | Rejected by the owner: it needs a master or a reachable central database |
| One portable build per machine with credentials inside | Rejected: heavy on every release |
| Credentials in the read-only catalog next to the engines | Rejected for the same reason |
| A catalog editor tool that writes the SQLite file directly | Possible later; not the default because the catalog would have no reviewable history |

## Open items

[PENDING] SQLite managed provider (Phase 1B, read-only open only). [PENDING] Manifest signing. [PENDING] Catalog authority: declarative source in this repository (proposed) or a catalog editor tool. [PENDING] Source of the secrets for the credential tool. [PENDING] Migration scope and cutover timing.

## Reopen conditions

The application needs to write configuration; more than one simultaneous operator becomes a requirement; a machine cannot be given its machine key or credentials file.
