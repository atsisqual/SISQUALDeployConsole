# Credential package (envelope)

**Status:** [PROPOSED] draft, version `0.1-proposed`. The algorithms and the trust bootstrap were approved by the owner (section 8). Reference implementation: `modules/Sisqual.Credentials` (B6.1a and B6.1b); a difference between this text and the module is fixed in the same PR.
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
KeyAlgorithm: ECDH-P256
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
| `encryption.keyWrap` | string | Exactly `ECDH-ES-P256-HKDF-SHA256`: the content key of each entry is derived from an ephemeral-static ECDH (P-256) with HKDF-SHA256 against the machine public key; any other value is a `VERSION` failure |
| `encryption.content` | string | Exactly `AES-256-GCM` for the authenticated encryption of each secret (12-byte nonce, 16-byte tag appended to the ciphertext); any other value is a `VERSION` failure |
| `entries[]` | array, 1..500 | One per credential |
| `entries[].credentialRef` | string `^[A-Z0-9_.:-]{1,120}$` | Stable reference used by engines; not secret |
| `entries[].kind` | enum | `IIS_IDENTITY`, `WEB_ACCESS`, `MOBILE_APP_TOKEN`, `RULE_SECRET` (Q6) |
| `entries[].instanceCode` | string, optional | Instance the credential belongs to |
| `entries[].wrappedKey` | base64 | The ephemeral public key (SubjectPublicKeyInfo, 91 bytes) of the ECDH-ES key agreement for this entry |
| `entries[].nonce` | base64 | Per-entry nonce, exactly 12 bytes |
| `entries[].ciphertext` | base64 | Authenticated ciphertext of the secret followed by the 16-byte tag (17 to 8208 bytes; the secret is 1 to 8192 bytes) |
| `signature.algorithm` | string | `ECDSA-P256-SHA256` (IEEE P1363, 64 bytes) |
| `signature.value` | base64 | Signature by the issuer key over the canonical bytes of the body without `signature` (the canonical form of the package manifest, RFC 8785 subset, Q2) |

Metadata (refs, kinds, instance codes) is not secret and is visible; only the secret values are ciphertext. Binding the entry's associated data to the target and `credentialRef` prevents moving an entry to another machine or credential.

[FIXED in B6.1] The body written in the armor is the canonical JSON of the whole object, signature included, so the signed bytes can be recomputed from it. Unknown members are refused at every level, including members that differ from a known one only by case, and so are duplicate members.

[FIXED in B6.1, change from the earlier draft] The field `entries[].aad` is NOT stored. The associated data is derived by both sides from the package fields, in this order, ASCII, separated by a line feed: the label `SISQUAL-CRED-AAD-v1`, `packageId`, `target.serverCode`, `target.keyFingerprint`, `credentialRef` and `sequence` in decimal. Storing a derivable value would only add something that could disagree with the fields.

[FIXED in B6.1] Content key: HKDF-SHA256 with the ECDH shared secret as input key material, salt = SHA-256 of (ephemeral public key || machine public key, both SubjectPublicKeyInfo), info = `SISQUAL credential entry v1`, 32 bytes.

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

[FIXED in `Test-CredentialPackage`] The result has `Ok`, `Reason` (the code of section 7a) and `Detail`, a field path and never a value. CRLF line endings are accepted (text pasted from a browser), everything else in check 1 is strict. The skew of 15 minutes applies to `issuedAt`; the lifetime limit is 366 days (a year that contains a leap day), and the builder issues 365 days by default.

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

[IMPLEMENTED in B6.1b] `tests/Unit/Test-CredentialPackage.ps1` covers every row except the last, which belongs to Phase 1B, and checks the reason code of each failure, the order of the checks, the format failures, the machine identity cases and that an entry cannot be moved to another reference, sequence, package or server.

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
- **Vault format [FIXED in B6.2a].** One ASCII text file, armored (`-----BEGIN SISQUAL VAULT-----`), whose body is the canonical JSON envelope `format`, `version`, `kdf` (`PBKDF2-HMAC-SHA256`, iterations, 16-byte salt), `cipher` (`AES-256-GCM`, 12-byte nonce) and `ciphertext` (ciphertext followed by the 16-byte tag). The associated data is the canonical JSON of the envelope without the ciphertext, so no header field can change. The iteration count is at least 600000 and a vault with fewer is refused. The vault holds the issuer key pair (K1) and, from B6.4, the credentials. A wrong passphrase and an altered file give the same generic failure. Saving is atomic (temporary file, then replace), keeps the previous generation as `.prev`, and refuses when the file changed since it was opened. The vault is refused inside a Git work tree, and on Windows its ACL is limited to the user, Administrators and SYSTEM. [PROPOSED] A minimum passphrase of 14 characters with at least 6 distinct ones; it is stricter than the contract required and the owner may relax it.
- **Issuer public key text [FIXED in B6.2b].** The text the operator pins on a machine (Q1) is ASCII, LF, armored (`-----BEGIN SISQUAL ISSUER KEY-----`) with the four fields `Contract`, `KeyId`, `KeyAlgorithm` (`ECDSA-P256`) and `PublicKey` (base64 SubjectPublicKeyInfo), in that order. `KeyId` is recomputed from the key and must match; a key that is not ECDSA P-256 is refused; any problem is the same generic error. `Format-KeyFingerprint` shows the key id as 16 groups of 4 so it can be compared on two screens before pinning.
- **Signer and verifier for the manifest [FIXED in B6.2b].** `tools/Sign-PackageManifest.ps1` is the `-SignerScript` of `Seal-Package`: it opens the vault (passphrase prompt that is never echoed), signs the canonical manifest bytes with the issuer key inside it, writes `{ issuerKeyId, algorithm, value }` with algorithm `ECDSA-P256-SHA256`, and only reads the vault. `tools/Verify-PackageSignature.ps1` is the `-VerifierScript`: it needs no passphrase, takes the pinned issuer key text, never trusts the key id written in the signature, and fails closed (exit 1) on a missing or invalid key file, an unreadable signature or any mismatch. Because `Seal-Package` passes no extra arguments, the vault path and the pinned key file come from `-VaultPath` / `SISQUAL_VAULT_PATH` and `-IssuerKeyFile` / `SISQUAL_ISSUER_KEY_FILE`, or from the ADR-0007 folder on Windows. [PROPOSED] For tests and unattended runs only, the passphrase may come from `SISQUAL_VAULT_PASSPHRASE`, and only together with `SISQUAL_ALLOW_ENV_PASSPHRASE=1`; the variable is removed from the process once read, and a redirected input never waits for a prompt.
- **Vault secrets [FIXED in B6.3a].** Each entry of the vault holds `credentialRef`, `kind`, `code`, `value` (base64 of the secret bytes, inside the encrypted data), `fingerprint`, `importedAt` and `source` (ASCII, at most 100 characters). The reference is derived and never typed: `<KIND>.<CODE>`, where the code is the instance code for `IIS_IDENTITY`, `WEB_ACCESS` and `MOBILE_APP_TOKEN` and the rule code for `RULE_SECRET`, in the characters `A-Z 0-9 _ -` (at most 60), so a reference stays unambiguous and within the pattern of section 3. A value has 1 to 8192 bytes and a vault holds at most 5000 entries. The fingerprint is the SHA-256 of a 16-byte salt followed by the value, lower-case hex; the salt is random, per vault and kept inside it, so a re-read of the source can be compared later without exposing the value (plan 4.2). An existing reference is never replaced unless explicitly asked. The vault keeps an access log of `ADD`, `REPLACE`, `REMOVE` and `READ` events with the reference and the time, never a value, capped at 10000 events. Reading a value returns a copy that the caller must clear.
- **Credential import [FIXED in B6.3b; the run against the live database is still to be done].** `tools/Import-CredentialsToVault.ps1` has three modes: `DryRun` (the default: reads and checks, writes nothing), `Import` (ALL OR NOTHING: any failure stops before anything is saved; an existing reference is refused unless `-Replace`; after the save every salted fingerprint is compared) and `Verify` (a fresh read compared with the fingerprints in the vault). It reads only through `app.GetManagedCredentialCatalogue` (which instances have which credentials, no secrets, no table permission needed), `app.GetManagedCredentialRuntime` (one instance at a time, decrypted through the certificate) and the three rule tables, over a read-only connection that validates the server certificate unless `-TrustServerCertificate` is given. The user name is not a secret and stays in the catalogue: the vault holds only the secret value. The literal rule secrets are selected exactly as `Protect-RuleRow` of the conversion tool selects them (a parity test keeps the two in step); on the current snapshot they are the 16 of `cfg.ConfigRule`, with no code collision. Failures are plain codes with references (`NULL_SECRET`, `MISSING`, `UNEXPECTED`, `DUPLICATE`, `TYPE`, `CODE`, `RULE_CODE_COLLISION`, `MISMATCH`, `NOT_IN_VAULT`); a value is never printed. The vault is opened before any secret is read. [V] On the live server, confirm that `app.GetManagedCredentialRuntime` writes no audit rows and changes no state, and which login may use the certificate.
- **Q10 Names and places [DECIDED, option A, read as "they fit"].** The manifest is `package-manifest.json` at the package root; the seal log is `<package folder>.seal.log` next to the folder, outside the package. (The question offered Sim/Nao; the owner answered "A". Read as yes.) [CONFIRMED by the owner, 2026-10-05, "Sim"] Read as yes.
- **Package file name [DECIDED, 2026-10-05].** The text package is saved as `credentials.pkg`.
