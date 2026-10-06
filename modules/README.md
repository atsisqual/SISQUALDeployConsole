# modules/

Shared PowerShell 7 modules used by the tools in `tools/` and, later, by the portable application.

Rules:
- A module contains NO key material and NO secret, and writes nothing to disk.
- ASCII and LF only; no `Invoke-Expression`; a unit test in `tests/Unit/` for every exported function.
- A module that the application needs is copied into the portable package and covered by its manifest.

| Module | State |
|---|---|
| `Sisqual.Credentials` | B6.2b adds the issuer public key text and the fingerprint display. B6.1a: canonical JSON (same as `tools/Seal-Package.ps1`), key fingerprint, ECDSA P-256 signature, ECDH-ES + HKDF + AES-256-GCM credential entries. B6.1b: machine identity text, credential package builder, the eight-check validator and per-entry decryption. Contract: `contracts/credential-package.md`. |
