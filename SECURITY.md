# Security policy

## Scope

SISQUALDeployConsole is a privileged Windows administration tool. Treat local HTTP, synchronized configuration, filesystem paths, SQL targets, IIS state, Windows services, Keycloak, TSplus, and credential packages as security-sensitive inputs.

## Repository rules

Never commit:

- real passwords or service-account secrets;
- private keys or certificate private material;
- bearer tokens, refresh tokens, or client secrets;
- production connection strings containing credentials;
- decrypted values from `sec.ManagedCredential` or equivalent secret-bearing views.

Use synthetic fixtures only.

## V1 trust boundaries

- [CONFIRMED] Central `_sisqualMANAGEMENT` configuration is authoritative and read-only from V1.
- [CONFIRMED] Pode binds to loopback only by default.
- [CONFIRMED] SQLite is local mirror/state and is not central authority.
- [CONFIRMED] IIS is accessed through `Microsoft.Web.Administration` under PowerShell 7, subject to ADR-0006 conditions.
- [PROPOSED] Credential packages are encrypted for a machine identity and signed by the signing identity of the credential tool (separate tool, outside the portable application; no permanent master server); the detailed contract remains subject to approval.

## Required controls

- validate Host and Origin before accepting browser mutations;
- require CSRF protection for mutating routes;
- deny CORS by default;
- use HttpOnly/SameSite session cookies;
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
