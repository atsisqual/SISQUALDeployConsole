# ADR-0007: Embedded read-only catalog, no runtime sync, text logs

**Status:** Accepted (2026-10-05). Direction given by the project owner in conversation; the owner answered the open questions and explicitly accepted the ADR on 2026-10-05. Decision items 4 and 9 (credentials) keep their [PROPOSED] label until the credential contract (`contracts/credential-package.md`, PR #13) is approved. The reviewer records the acceptance in `docs/decisions-log.md`.
**Supersedes in part:** ADR-0001 (SQLite as a local cache synchronised from the central database) and the decision of 2026-10-05 "central sync transport: direct read-only SQL" (there is no central database to read from any more; a one-time migration tool reads `_sisqualMANAGEMENT` read-only to produce the initial catalog source). The planned ADR on the central sync model is replaced by this one.

## Context

The owner does not want a master server, and `_sisqualMANAGEMENT` ceases to exist (the SQL Server databases of the managed instances remain). Updating means replacing the whole portable folder. The database must be read-only. Logs must be plain text in a configurable folder.

## Decision

1. **Catalog.** The configuration catalog is a SQLite file shipped inside the portable. The application opens it read-only and never writes to it. [DEFERRED by the owner] The long-term authority (declarative source in this repository compiled by a build tool, or a catalog editor tool) is decided later; in V1 the owner may edit the catalog manually (see 7). A one-time migration tool reads `_sisqualMANAGEMENT` read-only to produce the initial source; after the cutover that database is decommissioned. Secret-bearing data never enters the catalog or the repository (R-026).
2. **Updates.** The whole portable folder is replaced (catalog, engines, UI). The application makes no runtime connection to SQL Server or to any remote server to obtain configuration.
3. **Integrity.** The package carries a manifest with the SHA-256 of every file, including the catalog, verified at startup. The UI shows the catalog source, build time and schema version, because a stale catalog is now the main risk. The manifest is signed with the issuer key of the credential tool (decided by the reviewer on the owner's delegation). The application refuses to start on a hash or signature mismatch, except with an explicit development flag that is logged and shown in the UI.
4. **Credentials [PROPOSED].** Stored in a separate SQLite file outside the portable folder, by default `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\credentials.db`, read-only at runtime, produced by the separate credential tool, which needs a source for the secrets once `_sisqualMANAGEMENT` is gone ([PENDING], see open items). Values are encrypted for the machine (content key wrapped with the machine public key, package signed by the tool), decrypted only in memory when needed and never logged. The private key is the non-exportable machine key created on the machine (Phase 1B) and also lives outside the portable folder, so replacing the portable keeps it. Rejected alternative: credentials inside the portable catalog, which needs one build per machine on every release.
5. **Local state.** The application writes no database. Operation history goes to the text logs; locks and idempotency tokens are kept in memory (V1 has a single operator).
6. **Logs.** Plain text files in a configurable folder, default `C:\SISQUALWFM\WFM.Logs\SISQUALDeployManagement\`. They never contain secrets or tokens (R-008). One file per day, kept 30 days, both configurable (confirmed by the owner on 2026-10-05).

7. **Catalog changes in V1.** The owner may edit the catalog SQLite file manually. A seal tool then recomputes the manifest hashes and signature; without it the startup check refuses the package.
8. **Conversion and per-machine catalogs.** A one-off conversion tool reads `_sisqualMANAGEMENT` read-only and writes one catalog per existing machine (`ServerCode`): the machine's own server and instances plus the shared definitions. Secret-bearing data, job history, housekeeping artifacts and stored engine scripts are not carried into the catalogs; engine scripts are exported as files for the porting phase.
9. **Credentials in two steps [PROPOSED].** A machine public key only exists after the portable has run once on that machine, so its `credentials.db` is issued in a second step. Before `_sisqualMANAGEMENT` is retired, the existing credentials are imported once into an encrypted vault file kept outside Git and outside the portable; the credential tool issues each machine's `credentials.db` from that vault.
10. **Cutover.** The first deployment is on a server without the current system. The current Management Console stays in production until the owner decides to switch each existing server.

## Consequences

- The snapshot sync phase and its failure modes disappear (R-002, R-003, R-036 mostly); new risk: a stale catalog is used without anyone noticing.
- The one-off conversion tool, the seal tool and the credential tool are separate tools under `tools/`, run on demand by a person, and are not part of the portable application.
- WAL and concurrent writers are no longer needed. The SQLite provider only has to open a file read-only.
- The roadmap changes: the sync phase is replaced by the one-off conversion and the seal tool, the credential package work becomes the credential tool, and the coexistence plan with the current Management Console becomes a cutover and decommission plan.

## Alternatives considered

| Option | Verdict |
|---|---|
| Local cache synchronised from a central database (ADR-0001) | Rejected by the owner: it needs a master or a reachable central database |
| One portable build per machine with credentials inside | Rejected: heavy on every release |
| Credentials in the read-only catalog next to the engines | Rejected for the same reason |
| A catalog editor tool that writes the SQLite file directly | Possible later; not the default because the catalog would have no reviewable history |

## Open items

[PENDING] SQLite managed provider (Phase 1B, read-only open only). [PENDING] Vault format and protection. [PENDING] Per-table slicing rules for the per-machine catalogs (the conversion plan). [DEFERRED] Long-term catalog authority.

## Reopen conditions

The application needs to write configuration; more than one simultaneous operator becomes a requirement; a machine cannot be given its machine key or credentials file.
