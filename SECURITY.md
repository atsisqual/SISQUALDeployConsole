# Security policy

## Scope

SISQUALDeployConsole is a privileged Windows administration tool. Treat local HTTP, the catalog and the package manifest, filesystem paths, SQL targets, IIS state, Windows services, Keycloak, TSplus, and credential packages as security-sensitive inputs.

## Repository rules

Never commit:

- real passwords or service-account secrets;
- private keys or certificate private material;
- bearer tokens, refresh tokens, or client secrets;
- production connection strings containing credentials;
- decrypted values from `sec.ManagedCredential` or equivalent secret-bearing views.

Use synthetic fixtures only.

## V1 trust boundaries

- [CONFIRMED] There is no central configuration database (owner decision of 2026-10-05, ADR-0007, accepted by the owner on 2026-10-05). The catalog is a read-only SQLite file inside the package; the application never writes it and never contacts a server to obtain configuration.
- [CONFIRMED] Pode binds to loopback only by default.
- [PROPOSED] The package manifest lists the SHA-256 of every file and is signed by the credential tool. The application refuses a package whose files or signature do not match, except with an explicit, logged development flag. The signature algorithm and the trust bootstrap are [PENDING] owner approval.
- [CONFIRMED] Secrets never enter a catalog, the package, the repository or the logs. Credentials live outside the portable folder.
- [CONFIRMED] IIS is accessed through `Microsoft.Web.Administration` under PowerShell 7, subject to ADR-0006 conditions.
- [PROPOSED] Credential packages are encrypted for a machine identity and signed by the signing identity of the credential tool (separate tool, outside the portable application; no permanent master server); the detailed contract remains subject to approval.

## Required controls

- validate Host and Origin before accepting browser mutations;
- require CSRF protection for mutating routes;
- deny CORS by default;
- use HttpOnly/SameSite session cookies;
- verify the package manifest, and validate a credential package, before using their contents;
- validate all target identifiers and paths;
- never execute browser-supplied raw SQL or shell fragments;
- never use `Invoke-Expression` with untrusted input;
- redact secrets from structured logs and error responses;
- use operation/idempotency identifiers for mutating requests;
- retain local evidence without storing secret plaintext.

## Reporting a vulnerability

Do not open a public issue containing exploit details, credentials, private hostnames, or production data. Report security findings through the organisation's approved internal security channel and reference the repository/commit privately.

## Validation status

Items marked `[V]` in ADRs, risk registers, contracts, or PRs are not production-proven until the required real Windows/SISQUAL validation is recorded.
