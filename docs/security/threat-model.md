# Threat model: SISQUALDeployConsole V1

**Status:** [PROPOSED] for review (task 4). Documentation only; it adds no control and changes no contract.
**Date:** 2026-10-05
**Basis:** ADR-0001, ADR-0006, ADR-0007, `contracts/credential-package.md` (sections 2 to 8), `contracts/api/openapi.yaml`, `SECURITY.md`, `AGENTS.md`, the conversion and seal tools (B1 to B5), the credential module B6.1a, the Phase 1A results, and `docs/phase0/risk-register.md` as updated in PR #30 (risks R-001 to R-049). **Stacked on PR #30**: merge it first, because this document cites R-044 to R-049.
Tags: [CONFIRMED] implemented and evidenced; [PROPOSED] design not yet implemented; [PENDING] gap or decision needed; [V] needs a real Windows/SISQUAL environment.
Method: STRIDE (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege) per component.

## 1. What is protected, and what is not claimed

SISQUALDeployConsole runs elevated on a SISQUAL Windows server, changes IIS, services, application files and databases on that server, and handles the credentials of those environments. A flaw is therefore a path to the server and to the customers' environments.

**Not defended (accepted limits):** a compromised operating system or an attacker who is already local administrator of the machine (the tool runs with the same rights); physical access; a compromised operator machine that holds the credential tool (section 5, C7); side channels; the security of IIS, Keycloak, SQL Server and TSplus themselves.

## 2. System overview

```
 operator browser --(loopback HTTP, session)--> Pode adapter --> application core --> engines --> IIS, services,
        |                                          |                  |                           files, SQL (instances),
        |                                          |                  +--> catalog (read-only SQLite)  Keycloak, TSplus
        |                                          +--> manifest check at start
        |                                          +--> credentials.pkg (outside the folder), machine key
 operator machine: credential tool (vault, issuer key) --text package, carried by the operator--> import route
 build and conversion: reference system --> Convert-ManagementDb --> catalog --> Seal-Package --> signed package
```

## 3. Assets

| ID | Asset | Where | Why it matters |
|---|---|---|---|
| A1 | Credentials: 191 instance credentials and 16 rule secrets | vault; packages; memory at use | access to every managed environment |
| A2 | Issuer private key | credential tool machine | forges manifests and packages |
| A3 | Machine private key | target machine, outside the folder | decrypts that machine's credentials |
| A4 | Vault passphrase and vault file | operator | only copy of A1 once the old database is retired |
| A5 | Catalog | package, per machine | what the tool will change; wrong data causes wrong changes |
| A6 | Manifest and signature | package | integrity of everything that runs |
| A7 | Managed servers: IIS, services, files, databases, Keycloak | the machine | what is operated on |
| A8 | Operation evidence | text logs | accountability and recovery |
| A9 | Portable runtime and vendored files | package | PowerShell, Pode, SQLite, SQL client, modules run elevated |
| A10 | Engine backups | backup root | hold old configuration files, including secrets |
| A11 | Reference repository and sync file | GitHub | 16 literal secrets in its history (R-048, accepted) |
| A12 | Operator session | browser and loopback | authority to run operations |

## 4. Trust boundaries

| ID | Boundary | Crossing |
|---|---|---|
| TB1 | browser and any other local process to the loopback listener | HTTP requests |
| TB2 | listener to application core | authenticated session only |
| TB3 | application to engines | allowlisted modules with typed arguments, never raw input |
| TB4 | engines to the managed objects | administrator rights |
| TB5 | portable folder to machine-local secrets | machine key and `credentials.pkg` live outside the folder |
| TB6 | operator machine to target machine | text package carried by a person |
| TB7 | repository and build to the released package | manifest and signature |
| TB8 | old system to the conversion tools | one-off, read-only |

Actors: the operator (trusted); another user or process on the same machine; a web page in the operator's browser; a network attacker; whoever can copy or replace the portable folder; whoever can write to the repository or to the reference repository; a supply-chain attacker on a dependency.

## 5. STRIDE per component

Status of a control: **[CONFIRMED]** implemented and tested in this repository; **[PROPOSED]** designed; **[PENDING]** open. Tests refer to section 7.

### C1. Loopback listener and REST API (Pode adapter)

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-API-1 | S | another local process or user connects and acts as the operator | one-time bootstrap token exchanged for an HttpOnly, SameSite session; token never in a URL or log [PROPOSED, Phase 1C] | R-009 | ST-01 |
| T-API-2 | S | a malicious web page or DNS rebinding reaches the loopback port | Host and Origin validation, CORS denied [PROPOSED] | R-009 | ST-02 |
| T-API-3 | T | cross-site request forgery on a mutating route | CSRF token header and SameSite; routes need session and token (the OpenAPI skeleton requires both) [PROPOSED] | R-009 | ST-03 |
| T-API-4 | T | a retry or double click runs an operation twice | idempotency key and operation id [PROPOSED] | R-031 | ST-05 |
| T-API-5 | R | an operation cannot be attributed | one line per operation with time, operation, instance, result, no secrets; V1 has a single operator [PROPOSED]; a local administrator can alter logs (accepted); tamper-evident logs [PENDING] | R-038 | ST-06 |
| T-API-6 | I | secrets or stack traces in responses or logs | problem+json without secrets, redaction, marker test [PROPOSED]; the tools already follow it [CONFIRMED] | R-008 | ST-06 |
| T-API-7 | I | script injection through catalog values shown in the UI or written into generated pages (links page, Pulse page) | output encoding, strict CSP, no inline script, templates from the catalog only [PROPOSED] | R-030 | ST-14 |
| T-API-8 | D | a long operation or a flood blocks the server | operation coordinator, request and body size limits (import limited to 256 KiB) [PROPOSED] | R-011 | ST-15 |
| T-API-9 | E | browser input chooses paths, SQL or commands | only ids from the catalog allowlist reach engines; no raw SQL, no `Invoke-Expression` [PROPOSED] | R-030, R-034 | ST-12, ST-13 |
| T-API-10 | E | the listener is reachable from the network | loopback only, refused through the non-loopback address (proven on two runner images) [CONFIRMED, spike] | R-009 | ST-04 |
| T-API-11 | S | the bootstrap token leaks through the browser history or process list | passed by a method that does not persist it; design not fixed [PENDING] | R-009 | ST-01 |

### C2. Portable folder and start-up

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-PKG-1 | T | a file of the folder is swapped (script, module, DLL, SQL client) before or after verification | manifest of SHA-256 of every file verified at start [PROPOSED; `Seal-Package -VerifyOnly` implements the check, CONFIRMED]; the folder must not be writable by non-administrators [PENDING]; check between verification and load (time of check to time of use) [PENDING] | R-035 | ST-07, ST-16 |
| T-PKG-2 | T | an older, validly signed folder is put back (rollback) | not covered by the manifest alone; needs a monotonic version or build counter checked against the last one run on the machine [PENDING] | R-035 | ST-10 |
| T-PKG-3 | S | a package made for machine A is used on machine B | `server_code` in catalog and signed manifest compared with the machine identity [PROPOSED]; the seal tool checks it against the manifest [CONFIRMED] | R-036 | ST-07, ST-09 |
| T-PKG-4 | E | the tool runs elevated from a folder a standard user can write | install location and ACL policy [PENDING] | R-034 | ST-16 |
| T-PKG-5 | D | a partial or corrupt copy | the application refuses to start and shows `INTEGRITY_ERROR` [PROPOSED] | R-002, R-003 | ST-07 |
| T-PKG-6 | I | the development flag that skips verification is used in production | explicit flag, logged, shown in the UI; whether release builds omit it [PENDING] | R-035 | ST-07 |

### C3. Catalog (read-only SQLite)

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-CAT-1 | T | a hand edit adds a wrong value, a destructive path or a secret | `Seal-Package` validates (integrity, foreign keys, one meta row, forbidden tables and columns, secret scan), shows what changed, asks to confirm, records the edit [CONFIRMED]; engines check allowed roots [PROPOSED]; who may edit and a second reader [PENDING] | R-047 | ST-11, ST-13 |
| T-CAT-2 | T | the catalog no longer matches the real servers, or a directory row in another machine's catalog is old | build time and source shown; reconversion and reseal before cutover; change freeze [PENDING] | R-044 | ST-07 |
| T-CAT-3 | I | secrets in the catalog | whitelist of 62 tables, excluded columns, redaction of the 16 literals, safety-net scan, `Test-CatalogConversion`, seal scan; 0 of 16 values found in the six real catalogs [CONFIRMED] | R-026, R-048 | ST-06, ST-11 |
| T-CAT-4 | E | SQL or command text stored as data is executed | never executed (AGENTS.md); a static check over the modules [PENDING] | R-027, R-019 | ST-12 |
| T-CAT-5 | S | the catalog of another machine is used | `server_code` check as in T-PKG-3 | R-036 | ST-09 |
| T-CAT-6 | I | cross-machine data in a catalog | only the public instance directory, no secret column, verified by the conversion (design of task 1c) [PROPOSED] | R-044 | ST-11 |
| T-CAT-7 | D | the file is corrupt | `integrity_check` at start [PROPOSED] | R-003 | ST-07 |

### C4. Manifest and signature

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-MAN-1 | S | a forged manifest | ECDSA P-256 with SHA-256 by the issuer key, public key pinned on the machine after an out-of-band fingerprint check; module and tests exist [CONFIRMED], application side [PROPOSED] | R-006, R-035 | ST-07, ST-08 |
| T-MAN-2 | T | a file or the manifest altered | hash, size and unlisted-file checks; forged signature and changed field detected [CONFIRMED, 71 unit checks] | R-002 | ST-07 |
| T-MAN-3 | T | ambiguity in the signed bytes lets a different document verify | one canonical form (RFC 8785 subset), verified against an independent implementation [CONFIRMED] | R-035 | ST-08 |
| T-MAN-4 | R | who sealed what and when | seal log outside the package [CONFIRMED]; the log itself is not signed [PENDING] | R-047 | ST-11 |

### C5. Credential package and import route

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-CRD-1 | S | a forged package | signature check with the pinned issuer key before any decryption [PROPOSED]; signature code tested [CONFIRMED] | R-006 | ST-08 |
| T-CRD-2 | T | an altered, wrong-machine, expired or replayed package | validation order of the contract (format, version, signature, server, key fingerprint, time window, sequence greater than the installed one, unique refs); reason codes without secrets [PROPOSED] | R-006, R-037 | ST-08 |
| T-CRD-3 | I | secrets exposed from the package or after import | per-entry ECDH and AES-256-GCM with the entry's context as associated data; decryption only at use, in memory; 74 module tests including a marker that must not leak [CONFIRMED] | R-005, R-008 | ST-06, ST-08 |
| T-CRD-4 | I | secrets linger in memory, dumps or crash reports | minimise lifetime, never log [PROPOSED]; dumps and PowerShell string handling [PENDING] | R-008 | ST-06 |
| T-CRD-5 | D | an oversized or malformed body | 256 KiB limit, strict parser, unknown members rejected [PROPOSED] | R-011 | ST-15 |
| T-CRD-6 | E | a non-operator imports a package | the route requires session and CSRF token [PROPOSED] | R-009 | ST-01, ST-03 |
| T-CRD-7 | R | an import cannot be traced | log package id, sequence, issuer fingerprint, result; no secrets [PROPOSED] | R-038 | ST-06 |

### C6. Machine key and `credentials.pkg`

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-KEY-1 | I, E | the private key travels with the folder or is exportable | non-exportable key created on the machine, stored outside the folder; two-VM copy test [PROPOSED, Phase 1B] | R-007 | ST-09 |
| T-KEY-2 | T | `credentials.pkg` is replaced by an older valid package | replay reference is the installed package's sequence; no separate state [PROPOSED] | R-037 | ST-08 |
| T-KEY-3 | D | key lost after a reinstall | reissue with a new identity text (manual, decided) | R-045 | ST-18 |

### C7. Credential tool: vault and issuer key (operator machine)

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-VLT-1 | I | the vault file is stolen and attacked offline | passphrase-derived key (PBKDF2-HMAC-SHA256, iteration count fixed at implementation), file outside Git and the portable, restricted permissions [PROPOSED]; passphrase strength rule [PENDING] | R-046 | ST-17 |
| T-VLT-2 | T | the vault is altered | authenticated encryption [PROPOSED] | R-046 | ST-17 |
| T-VLT-3 | S | the issuer private key is stolen | storage and custody not decided [PENDING]; procedure if compromised: new key and new pin on each of the six machines (decided as manual) | R-045 | ST-18 |
| T-VLT-4 | D | passphrase, vault or issuer key lost | two encrypted backups in two places, restore tested [PROPOSED]; a second custodian [PENDING] | R-046, R-045 | ST-17 |
| T-VLT-5 | I | plaintext in logs or transcripts | the tool logs counts and references only; marker tests [PROPOSED] | R-008 | ST-06 |
| T-VLT-6 | E | the operator machine is compromised | accepted limit (section 1); hardening of that machine is outside this tool | R-045 | - |

### C8. Conversion, verification, seal and client tools

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-TLS-1 | I | the sync file (16 literal secrets) reaches the repository, CI or a log | never copied into the repository or CI; downloaded outside Git; tools print counts only [CONFIRMED]; secret scan in CI on changed files | R-048 | ST-06 |
| T-TLS-2 | T | a conversion bug lets a secret or a wrong value through | whitelist, exclusion by name, redaction, safety net, value-level verification, an independent Python check, mutation-checked tests [CONFIRMED] | R-026 | ST-11 |
| T-TLS-3 | T | a tampered SQL client or runtime | per-file SHA-256 pins and the Microsoft signature checked at pin time [CONFIRMED]; delivery to the package [PENDING] | R-035, R-049 | ST-20 |
| T-TLS-4 | T | the seal tool signs something unreviewed | dry run, summary of changed files and tables, confirmation, rollback on failure [CONFIRMED] | R-047 | ST-11 |
| T-TLS-5 | S | a malicious signer script is supplied | the tool never sees a key and validates the returned shape; a signer can only return a signature [CONFIRMED]; where the real signer is stored [PENDING] | R-045 | ST-08 |

### C9. Engines

| ID | STRIDE | Threat | Control | Risk | Test |
|---|---|---|---|---|---|
| T-ENG-1 | T | the wrong instance, site, pool or service is changed | ownership checks, allowlists, preview and apply with the same fingerprint, per-instance and server locks [PROPOSED] | R-012, R-021, R-023 to R-025, R-032 | ST-13 |
| T-ENG-2 | T | an engine runs data as code | local versioned modules only; a static check for dynamic evaluation [PENDING] | R-027 | ST-12 |
| T-ENG-3 | I | secrets in engine results, logs, status files or backups | redaction by rule code, marker tests per engine [PROPOSED]; backup folder restricted and retention [PENDING] | R-008, R-033 | ST-06 |
| T-ENG-4 | T | a path built from catalog templates escapes the allowed root | canonicalise and check against allowed roots [PROPOSED] | R-030 | ST-13 |
| T-ENG-5 | D | a crash during a change | atomic writes, backup before change, recovery evidence kept [PROPOSED] | R-014, R-033 | ST-13 |
| T-ENG-6 | S | outbound health checks trust any certificate | validate by default, exceptions explicit (Pulse spec) [PROPOSED] | R-034 | ST-19 |
| T-ENG-7 | E | a task or service registered with the instance identity runs more than needed | per-engine review of the identity and rights [PENDING] | R-034 | - |

## 6. Cross-cutting points

- **Single operator, elevated process.** V1 has no user model beyond the bootstrap session; a session is full authority (R-034). [PENDING] whether the application should require the Windows user to be an administrator and record that user in the log.
- **Time.** Package expiry and clock skew depend on the machine clock (R-037); a wrong clock can accept an expired package or refuse a valid one.
- **Updates.** Updating replaces the whole folder; authenticity comes from the signature, freshness from nothing yet (T-PKG-2).
- **Data classification.** The catalog holds host names, customer names and paths (internal); it holds no secret by construction. Packages are confidential even though encrypted (metadata is visible).

## 7. Tests required

Status: **exists** (in this repository and in CI), **planned** (needs code that does not exist yet), **[V]**. Tests live under `tests/Security` or the folder of their kind.

| ID | Test | Covers | Status |
|---|---|---|---|
| ST-01 | the bootstrap token works once; a second use, an expired token and a guessed token fail; the token is not logged | T-API-1, 11, T-CRD-6 | planned (1C) |
| ST-02 | a wrong Host or Origin is refused; CORS is denied | T-API-2 | planned (1C) |
| ST-03 | a mutating route without or with a wrong CSRF token is refused | T-API-3, T-CRD-6 | planned (1C) |
| ST-04 | the listener refuses connections through a non-loopback address | T-API-10 | spike exists; product test planned |
| ST-05 | a duplicate request creates one operation | T-API-4 | planned |
| ST-06 | a marker credential never appears in logs, results, API responses, status files or backups | T-API-5, 6, T-CRD-3, 4, 7, T-VLT-5, T-TLS-1, T-CAT-3, T-ENG-3 | exists for the tools and the module; planned for the application and each engine |
| ST-07 | start-up verification: changed, missing, extra file, bad signature and a foreign catalog give `INTEGRITY_ERROR` | T-PKG-1, 3, 5, 6, T-CAT-2, 7, T-MAN-1, 2 | tool level exists (`Seal-Package`); application level planned |
| ST-08 | the contract's negative tests for the credential package, plus signature tests | T-CRD-1 to 3, T-MAN-1, 3, T-KEY-2, T-TLS-5 | module tests exist (74); import-route tests planned |
| ST-09 | copying the folder or the catalog to another machine yields no usable identity or catalog | T-KEY-1, T-PKG-3, T-CAT-5 | planned (1B, two runner VMs) |
| ST-10 | an older validly signed folder is refused | T-PKG-2 | planned, if the decision is taken |
| ST-11 | the seal tool refuses secrets, forbidden columns, tables and files; the conversion tests pass | T-CAT-1, 3, 6, T-TLS-2, 4, T-MAN-4 | exists |
| ST-12 | static check: no dynamic code evaluation, no execution of catalog text, no raw SQL from request data | T-CAT-4, T-API-9, T-ENG-2 | planned (`tests/Static`) |
| ST-13 | path traversal, an instance of another machine and an off-list code are refused | T-API-9, T-CAT-1, T-ENG-1, 4, 5 | planned per engine |
| ST-14 | HTML and script in catalog values are encoded in the UI and in generated pages | T-API-7 | planned |
| ST-15 | oversized bodies and imports are refused | T-API-8, T-CRD-5 | planned |
| ST-16 | a standard user cannot modify the installed folder | T-PKG-1, 4 | planned, [V] |
| ST-17 | vault: wrong passphrase fails, tampering is detected, restore from a backup works | T-VLT-1, 2, 4 | planned (B6) |
| ST-18 | issuer key compromise and machine key loss drills (reissue, re-pin) | T-VLT-3, T-KEY-3 | planned, [V] |
| ST-19 | outbound checks validate certificates by default | T-ENG-6 | planned |
| ST-20 | pinned dependencies are verified before use | T-TLS-3 | exists for the SQL client and the sqlite3 archive; planned for the rest |

## 8. Gaps [PENDING]

Each with a recommendation; none is an owner decision.

1. Session design (token transport, expiry, binding): recommend the design in Phase 1C before any mutating route exists.
2. Install location and ACL of the portable folder, and a check between verification and load: recommend a protected folder and verifying again before loading each module.
3. Rollback of an older signed folder: recommend a monotonic counter in the manifest checked against the last run on the machine (a contract change, to be approved).
4. Whether release builds omit the development flag: recommend yes.
5. Issuer key storage and custody, second custodian of the vault passphrase (R-045, R-046).
6. Tamper-evident logs: recommend a hash chain per day; low priority while there is a single operator.
7. Secrets in memory and crash dumps: recommend disabling dumps for the process and minimising lifetime.
8. Identity and rights of tasks and services created by engines (Pulse task, Windows services): review in each engine spec.
9. Review cadence: update this document at each phase gate (1B, 1C, 3, first mutating engine, ADR-0006 conditions, acceptance) and whenever a contract changes.
