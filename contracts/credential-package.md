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
| Vault | outside Git and outside the portable, on the tool operator's machine | credential tool | credential tool | all credentials, encrypted [PENDING format] |
| Issuer key pair | tool operator's machine; private key never leaves it | credential tool | credential tool (private); portable and tool (public) | signing identity |
| Machine key pair | target machine, outside the portable folder; private key non-exportable (Phase 1B, CNG or machine-scope DPAPI [PENDING]) | portable application, first run | portable application | machine identity |
| Machine identity text | exported by the application, carried by the operator | portable application | credential tool | public key, fingerprint, ServerCode, machine name (informational) |
| Credential package | text, carried by the operator | credential tool | portable application | ciphertext entries for ONE machine |
| Imported credentials (`credentials.db` by default `C:\SISQUALWFM\WFM.Files\SISQUALDeployManagement\credentials.db`, ADR-0007) | target machine, outside the portable | see open question Q3 | portable application, read-only at runtime | the package entries still encrypted |

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
KeyAlgorithm: <PENDING identifier>
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
| `expiresAt` | UTC time | After this time the package is unusable; maximum lifetime [PENDING] |
| `issuer.keyId` | 64 lowercase hex | SHA-256 fingerprint of the issuer public key |
| `target.serverCode` | string `^[A-Za-z0-9_-]{1,60}$` | Must equal the ServerCode of the catalog in use |
| `target.keyFingerprint` | 64 lowercase hex | Must equal the fingerprint of the local machine key |
| `target.machineName` | string, optional | Informational, never used to authorise |
| `encryption.keyWrap` | string | [PENDING] algorithm identifier for wrapping each content key to the machine public key |
| `encryption.content` | string | [PENDING] algorithm identifier for the authenticated encryption of each secret |
| `entries[]` | array, 1..500 | One per credential |
| `entries[].credentialRef` | string `^[A-Z0-9_.:-]{1,120}$` | Stable reference used by engines; not secret |
| `entries[].kind` | enum | `SQL_LOGIN`, `WINDOWS_ACCOUNT`, `KEYCLOAK_CLIENT_SECRET`, `OTHER` [PENDING list from the credential inventory] |
| `entries[].instanceCode` | string, optional | Instance the credential belongs to |
| `entries[].wrappedKey` | base64 | Content key wrapped for the machine key |
| `entries[].nonce` | base64 | Per-entry nonce |
| `entries[].ciphertext` | base64 | Authenticated ciphertext of the secret |
| `entries[].aad` | string | Associated data bound to the entry: `packageId`, `target.serverCode`, `target.keyFingerprint`, `credentialRef`, `sequence` in a fixed order [PENDING exact layout] |
| `signature.algorithm` | string | [PENDING] algorithm identifier |
| `signature.value` | base64 | Signature by the issuer key over the canonical body without `signature` [PENDING canonical form] |

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
6. Time window: `notBefore` <= now <= `expiresAt`, with `issuedAt` not in the future beyond a tolerated skew [PENDING value]. The check needs a trustworthy clock (R-037).
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

## 8. Open questions (all [PENDING], need owner approval)

- **Q1 Trust bootstrap.** How does the application learn which issuer public key to trust? Options: pinned in the signed portable and confirmed once by the operator by comparing a fingerprint out of band; or pinned on the machine at first import in a file outside the portable. A key shipped only inside a replaceable folder protects nothing against someone who can replace the folder.
- **Q2 Algorithms and canonical form.** Key wrap, authenticated encryption, signature, hash for fingerprints, canonicalisation of the signed body. To be proposed in the machine-key ADR (Phase 1B).
- **Q3 Import destination.** The owner's decision says the package is imported as text; ADR-0007 item 4 and the conversion plan speak of the tool issuing a `credentials.db`. Is `credentials.db` the same envelope rows written by an import step, or a file the tool produces and the operator copies? ADR-0007 also says the application writes no database, so a text import that writes a file needs an explicit exception or an import step in a tool.
- **Q4 Replay state.** `sequence` needs persistent storage outside the portable folder. This conflicts with "application writes no database" unless the import step owns it.
- **Q5 Key loss and rotation.** A recreated machine key changes the fingerprint and invalidates the package; the reissue procedure and the rotation of issuer keys must be defined.
- **Q6 Credential inventory.** The list of credential kinds depends on the conversion plan (sec.ManagedCredential and equivalents).
- **Q7 Lifetime and skew.** Maximum package lifetime and tolerated clock skew.
- **Q8 One package per machine or per instance.** This draft uses one package per machine with many entries.
