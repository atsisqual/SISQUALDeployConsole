# Credential package (envelope)

**Status:** [PROPOSED] draft, version `0.1-proposed`. Not approved. No cryptographic code and no algorithm choice is made here: AGENTS.md requires owner approval for algorithms, key ownership, trust bootstrap and envelope semantics.
**Basis:** owner decisions of 2026-10-05 (below), ADR-0007 (accepted 2026-10-05; its credential items 4 and 9 stay [PROPOSED]), risk register R-005, R-006, R-007, R-008, R-036, R-037.
Tags: [CONFIRMED] owner decision; [PROPOSED] draft design; [PENDING] open decision; [V] only verifiable on a real machine.

## 1. Owner decisions that shape this contract

- [CONFIRMED] Credentials are produced by a SEPARATE tool under `tools/`, outside the portable application. It generates a package or key valid for ONE target machine only.
- [CONFIRMED] The portable application never contacts any server to obtain or exchange credentials. There is no permanent master server.
- [CONFIRMED] The package is bound to the target machine, signed by the tool and imported manually as text.
- [CONFIRMED] The signing identity is the identity of the credential tool (not a central server). The package manifest of the portable is signed with the same issuer key (ADR-0007 item 3, decided by the reviewer on the owner's delegation).
- [PROPOSED] The existing credentials are imported once into an encrypted vault kept outside Git and outside the portable; the tool issues each machine's package from that vault (ADR-0007 item 9; vault format and protection are in `docs/migration/catalog-conversion-plan.md` once approved).

## 2. Artefacts and who owns them

| Artefact | Lives where | Written by | Read by | Contains |
|---|---|---|---|---|
| Vault | outside Git and outside the portable, on the tool operator's machine | credential tool | credential tool | all credentials, encrypted with a key derived from the owner's passphrase (Q9) |
| Issuer key pair | tool operator's machine; private key never leaves it | credential tool | credential tool (private); portable and tool (public) | signing identity |
| Machine key pair | target machine, outside the portable folder; private key non-exportable (Phase 1B, CNG or machine-scope DPAPI [PENDING]) | portable application, first run | portable application | machine identity |
| Machine identity text | exported by the application, carried by the operator | portable application | credential tool | public key, fingerprint, ServerCode, machine name (informational) |
| Credential package | text, carried by the operator | credential tool | portable application | ciphertext entries for ONE machine |
| Imported credential package (`credentials.pkg` by default `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\credentials.pkg`, Q3) | target machine, outside the portable | the application's import route, only | portable application | the signed package as received, entries still encrypted |

## 3. Lifecycle

1. [PROPOSED] **Vault load (once).** Before `_sisqualMANAGEMENT` is retired, the current credentials are imported into the vault by the credential tool. Not part of the portable and not part of this contract's runtime.
2. [PROPOSED] **Machine identity.** The portable runs once on the target machine, creates the non-exportable machine key and shows the machine identity text (section 4). The application does not send it anywhere; the operator carries it to the tool.
3. [PROPOSED] **Issue.** The operator gives the machine identity text to the tool and chooses which instances' credentials the machine needs. The tool encrypts each entry for that machine key, signs the whole package and prints the package as text.
4. [PROPOSED] **Import.** The operator pastes or loads the package text into the application on the target machine (import is manual). The application validates it (section 6) and keeps it for use.
5. [PROPOSED] **Use.** An engine asks for a credential by `credentialRef`. The application decrypts that entry in memory with the machine key, hands it to the engine in memory and discards it. It is never written, logged or returned by the API.
6. [PROPOSED] **Replace.** A newer package (higher `sequence`) replaces the previous one as a whole. Revocation is replacement or expiry; there is no online revocation list.

## 3a. Machine identity text

[PROPOSED] ASCII text produced by the application:

```
-----BEGIN SISQUAL MACHINE IDENTITY-----
Contract: 0.1-proposed
ServerCode: EXAMPLE_SERVER
MachineName: EXAMPLE-HOST
KeyFingerprint: <sha256 of the machine public key, 64 lowercase hex>
KeyAlgorithm: ECDH-P256 [PROPOSED identifier]
PublicKey: <base64>
CreatedAt: 2026-01-01T00:00:00Z
-----END SISQUAL MACHINE IDENTITY-----
```

`ServerCode` comes from the catalog. `MachineName` is informational only and is not a binding (machines can be renamed); the binding is `ServerCode` plus `KeyFingerprint`.

## 4. Package format

[PROPOSED] One text document, ASCII, LF only, at most 256 KiB:

```
-----BEGIN SISQUAL CREDENTIAL PACKAGE-----
<base64 of the JSON body, wrapped at 76 characters>
-----END SISQUAL CREDENTIAL PACKAGE-----
```

The decoded body is JSON (UTF-8 limited to ASCII; non-ASCII is escaped). Unknown members are rejected.

| Field | Type | Rule |
|---|---|---|
| `contractVersion` | string | Must be a version the application supports; `0.1-proposed` for this draft |
| `packageId` | uuid | Unique per package |
| `sequence` | integer >= 1 | Strictly increasing per target machine; used for replay protection |
| `issuedAt` | UTC time `YYYY-MM-DDTHH:MM:SSZ` | Not in the future beyond the allowed skew |
| `notBefore` | UTC time, optional | Package unusable before this time |
| `expiresAt` | UTC time | After this time the package is unusable; maximum lifetime 1 year (Q7) |
| `issuer.keyId` | 64 lowercase hex | SHA-256 fingerprint of the issuer public key |
| `target.serverCode` | string `^[A-Za-z0-9_-]{1,60}$` | Must equal the ServerCode of the catalog in use |
| `target.keyFingerprint` | 64 lowercase hex | Must equal the fingerprint of the local machine key |
| `target.machineName` | string, optional | Informational, never used to authorise |
| `encryption.keyWrap` | string | `ECDH-ES-P256-HKDF-SHA256` [PROPOSED identifier]: the content key of each entry is derived from an ephemeral-static ECDH (P-256) with HKDF-SHA256 against the machine public key |
| `encryption.content` | string | `AES-256-GCM` [PROPOSED identifier] for the authenticated encryption of each secret |
| `entries[]` | array, 1..500 | One per credential |
| `entries[].credentialRef` | string `^[A-Z0-9_.:-]{1,120}$` | Stable reference used by engines; not secret |
| `entries[].kind` | enum | `IIS_IDENTITY`, `WEB_ACCESS`, `MOBILE_APP_TOKEN`, `RULE_SECRET` (Q6) |
| `entries[].instanceCode` | string, optional | Instance the credential belongs to |
| `entries[].wrappedKey` | base64 | Content key wrapped for the machine key |
| `entries[].nonce` | base64 | Per-entry nonce |
| `entries[].ciphertext` | base64 | Authenticated ciphertext of the secret |
| `entries[].aad` | string | Associated data bound to the entry: `packageId`, `target.serverCode`, `target.keyFingerprint`, `credentialRef`, `sequence` in a fixed order [PENDING exact layout] |
| `signature.algorithm` | string | `ECDSA-P256-SHA256` [PROPOSED identifier] |
| `signature.value` | base64 | Signature by the issuer key over the canonical body without `signature` canonical form as in the package manifest (RFC 8785 subset, Q2) |

Metadata (refs, kinds, instance codes) is not secret and is visible; only the secret values are ciphertext. Binding the entry's associated data to the target and `credentialRef` prevents moving an entry to another machine or credential.

## 5. What is never in a package

- Plaintext secrets, private keys, or connection strings with passwords.
- Anything that identifies a real server in examples or tests committed to the repository.

## 6. Validation order before any decryption

[PROPOSED] The application stops at the first failure, reports a reason code without secret content, and decrypts nothing until all checks pass.

1. Armor lines, ASCII, size limit, base64, JSON well-formed, no unknown members, field formats.
2. `contractVersion` supported.
3. Signature valid, made by a trusted issuer key (trust bootstrap: Q1).
4. `target.serverCode` equals the catalog ServerCode.
5. `target.keyFingerprint` equals the local machine key fingerprint (wrong machine or regenerated key fails here).
6. Time window: `notBefore` <= now <= `expiresAt`, with `issuedAt` not in the future beyond a tolerated skew of 15 minutes (Q7). The check needs a trustworthy clock (R-037).
7. `sequence` greater than the last accepted sequence for this machine (replay protection; storage: Q4).
8. Every `entries[].credentialRef` unique.

Decryption happens per entry at use time, in memory, and failure of one entry does not leak which part failed beyond a reason code.

## 7. Negative tests required before approval

[PROPOSED] Using invented test keys only, never real ones:

| Test | Expected |
|---|---|
| Package for machine A imported on machine B (same folder copied) | Fails at check 5 |
| Body altered (one entry or metadata) | Fails at check 3 |
| Valid package re-imported with the same or lower `sequence` | Fails at check 7 |
| Expired package, and package not yet valid | Fails at check 6 |
| Wrong `serverCode` | Fails at check 4 |
| Signed by an unknown issuer key | Fails at check 3 |
| Marker secret planted in the vault | Marker absent from logs, API responses, transcripts and imported files in clear |
| Portable folder copied to another machine | No usable machine identity travels with it (Phase 1B) |

## 7a. Failure reasons (no secret content)

[PROPOSED] reason codes: `FORMAT`, `VERSION`, `SIGNATURE`, `TARGET_SERVER`, `TARGET_KEY`, `TIME_WINDOW`, `REPLAY`, `DUPLICATE_REF`.

## 8. Owner answers (2026-10-05)

Each answer is traceable to the owner's reply of 2026-10-05 ("Q1. A", "Q2. A", and so on, to the questions listed in the conversation). Tags: [DECIDED] answered by the owner; [PROPOSED] detail that follows from the answer and still needs the implementation to prove it; [PENDING] not answered.

- **Q1 Trust bootstrap [DECIDED, option A].** The issuer public key is pinned on the machine, outside the portable folder, at the first import, after the operator confirms the issuer key fingerprint shown by the credential tool against the one shown by the application (out of band). A key shipped only inside the replaceable portable folder is not trusted.
- **Q2 Algorithms [DECIDED, option A].** Signature: ECDSA P-256 with SHA-256. Credential entries: a content key derived by ephemeral-static ECDH (P-256) against the machine key, then AES-256-GCM. Fingerprints: SHA-256. All of it is in .NET, no new dependency. [PROPOSED] the key derivation step uses HKDF-SHA256 and the algorithm identifiers in section 4; the exact associated-data layout is fixed by the implementation and covered by the negative tests. The canonical form of the signed bytes is the RFC 8785 subset implemented by `tools/Seal-Package.ps1` (the owner answered "A" to Q2, which asked to approve it; if that was not meant, say so). [CONFIRMED by the owner, 2026-10-05, "Sim"] Option A also approves the canonical form of the signed bytes used by `Seal-Package`.
- **Q3 Import destination [DECIDED, option A].** The operator pastes the text package into the application (`POST /credentials/import`). The application validates it (the checks of section 6 that need no private key: format, version, signature with the pinned issuer key, target server, key fingerprint, time window, sequence greater than the installed package's) and stores it as received, still encrypted, in a file outside the portable folder, by default `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\credentials.pkg` [PROPOSED file name; ADR-0007 said `credentials.db`]. That file is the application's only write besides the text logs; there is no database. [PROPOSED] controls: the route needs the session and the CSRF token, the body is limited to 256 KiB and never logged, the write is atomic (temporary file, then rename), and the previous package stays until the new one validates. Decryption of an entry happens only at use, in memory, with the machine key.
- **Q4 Replay protection [DECIDED, option A].** The sequence number of the package already installed on the machine is the reference: a new package is accepted only with a greater sequence. No extra state is stored.
- **Q5 Key loss and rotation [DECIDED, option A].** Everything is manual: a new machine identity, a new package, and the issuer public key is pinned again on each machine (six machines).
- **Q6 Credential kinds [DECIDED, option A].** Four kinds: `IIS_IDENTITY` (76), `WEB_ACCESS` (76), `MOBILE_APP_TOKEN` (39) and `RULE_SECRET` (the 16 literal secrets found in `cfg.ConfigRule`). [DECIDED, owner: "Nao", 2026-10-05] The 16 exposed secrets are NOT rotated after the cutover; the owner accepts the risk that they remain readable in the history of the reference repository.
- **Q7 Lifetime and clock [DECIDED, option A].** Maximum package lifetime 1 year; tolerated clock skew 15 minutes.
- **Q8 Granularity [DECIDED, option A].** One package per machine, with the credentials of that machine's instances (and the `RULE_SECRET` entries its engines need).
- **Q9 Vault protection [DECIDED, option A].** One encrypted file outside Git, protected by the owner's passphrase through PBKDF2-HMAC-SHA256 [PROPOSED: the iteration count is fixed at implementation, at least the current OWASP guidance], two encrypted backups kept in two places, restore tested. No binding to a Windows account.
- **Q10 Names and places [DECIDED, option A, read as "they fit"].** The manifest is `package-manifest.json` at the package root; the seal log is `<package folder>.seal.log` next to the folder, outside the package. (The question offered Sim/Nao; the owner answered "A". Read as yes.) [CONFIRMED by the owner, 2026-10-05, "Sim"] Read as yes.
- **Package file name [DECIDED, 2026-10-05].** The text package is saved as `credentials.pkg`.
