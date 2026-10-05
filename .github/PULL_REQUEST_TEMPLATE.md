## Scope

Describe the single task covered by this PR.

## Evidence

- [ ] `[CONFIRMED]` evidence is linked or named.
- [ ] `[PROPOSED]` decisions are clearly marked.
- [ ] `[PENDING]` items are listed below.
- [ ] `[V]` items name the required validation environment.

## Safety

- [ ] No real credentials, tokens, keys, or production secrets.
- [ ] The application does not write the catalog or contact a server for configuration, and no secret is in a catalog, package or log.
- [ ] No unapproved destructive operation.
- [ ] `atsisqual/SISQUALManagementConsole` was treated as read-only reference.

## Validation

- [ ] Changed PowerShell parses with the PowerShell 7 parser (and with Windows PowerShell 5.1 if it is a designated fallback script).
- [ ] Changed text files use ASCII and LF unless approved evidence requires otherwise.
- [ ] Relevant tests/checks pass.

## Remaining decisions

List all `[PENDING]` and `[V]` items.
