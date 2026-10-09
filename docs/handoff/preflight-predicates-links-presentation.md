# DEPLOYMENT_PREFLIGHT predicates: Links presentation resources

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewLinksPagePresentationResources`
**Verification base:** `main@a32141cbec584d349f1591a4aa5a801137463278`

## Evidence boundary

The predicate source is `docs/handoff/preflight-legacy-procedures.sql.txt` at the verification base. The requested D13e port set and rules 6 and 7 come from `docs/handoff/preflight-port-gap.md` on read-only PR #69 head `80240090ba5dc37e13a64d359f9378a1c033fcc4`.

SQLite table and column names were checked against `tests/Fixtures/carried-schema.json` at the verification base. `cfg.LinksPagePresentationResource` maps to `cfg_LinksPagePresentationResource`; the carried columns used by the requested predicate are `ResourceCode`, `ResourceText`, `ContentSha256`, and `IsEnabled`.

The requested `tests/Fixtures/preflight-legacy-codes.json` is not present in `main@a32141cbec584d349f1591a4aa5a801137463278`. The requested code's severity is therefore checked against the literal extracted T-SQL and the one-code table in `preflight-port-gap.md`; both say `ERROR`.

### Source-inventory discrepancy

The exact extracted procedure emits two issue codes: `LINKS_PRESENTATION_RESOURCE_MISSING` and `LINKS_PRESENTATION_HASH_MISMATCH`. The supplied port gap says only one code from this procedure remains to port and lists only `LINKS_PRESENTATION_HASH_MISMATCH`; the D13 task likewise assigns one code to D13e. This document therefore specifies only that requested code and does not silently create a 31st unported item.

**[PENDING] Question:** before implementation, should the source inventory / legacy-code fixture / port-gap count be amended to include `LINKS_PRESENTATION_RESOURCE_MISSING`, or is that code intentionally excluded by a decision not present in the supplied sources? Until that is answered, do not infer an implementation requirement for the extra code from its name.

## `LINKS_PRESENTATION_HASH_MISMATCH`

**Verbatim T-SQL predicate:**

```sql
FROM cfg.LinksPagePresentationResource AS P
WHERE P.IsEnabled = 1
  AND P.ContentSha256 <>
      LOWER
      (
          CONVERT
          (
              char(64),
              HASHBYTES('SHA2_256',CONVERT(varbinary(max),P.ResourceText)),
              2
          )
      )
```

**SQLite inputs:** `cfg_LinksPagePresentationResource(ResourceCode, ResourceText, ContentSha256, IsEnabled)`. All four columns are present in `carried-schema.json`. `ContentSha256` is a 64-character hash field. `ModifiedAt` is not used by the predicate and is intentionally omitted.

**Original severity:** `ERROR`.

**Rule 6:** No instance-to-instance comparison is present. This validates each enabled global presentation resource independently. In a one-instance `DEPLOYMENT_PREFLIGHT` request, report a mismatch on the selected instance and retain the failing `ResourceCode` as the object/resource identifier. Do not create a comparison against other selected or enabled instances because the source predicate has none.

**Rule 7:** No catalog filesystem path is used. `ResourceText` is hashed in memory; no existence/read/write probe is part of this predicate, so real-path resolution and containment do not apply here.

**Text comparison:** The procedure has no `COLLATE`. The hash input is not ordinary text equality: SQL Server first executes `CONVERT(varbinary(max), P.ResourceText)` where `ResourceText` is `nvarchar`, then hashes those bytes. The portable test/port must preserve that SQL Server Unicode byte representation rather than silently hashing UTF-8 text; include a non-ASCII text case to prove byte parity. The final `P.ContentSha256 <> LOWER(computed_hex)` is a text comparison under the unknown source database collation. The computed side is explicitly lowercase but the stored side is not normalized. **[PENDING]** Decide whether an uppercase stored hexadecimal representation of the same digest is accepted or reported as a mismatch. Do not infer this from the code name or from the usual case-insensitive SQL Server default.

**Tests:**

- Trigger: an enabled resource has `ResourceText` whose SQL Server-compatible SHA-256 bytes no longer match `ContentSha256`; expect exactly `LINKS_PRESENTATION_HASH_MISMATCH` with `ERROR`.
- Non-trigger: an enabled resource stores the lowercase 64-character SHA-256 of the SQL Server `nvarchar` byte representation of its `ResourceText`; no issue.
- Boundary: use `ResourceText` containing at least one non-ASCII character and verify the portable hash uses the same bytes as `CONVERT(varbinary(max), nvarchar)` rather than UTF-8. Separately, store the same digest in uppercase hexadecimal; the expected case-only comparison result remains **[PENDING]** the collation decision above.

**Ambiguity:** The predicate shape, carried columns, hash algorithm, enabled-row filter, and severity are unambiguous. Two questions remain: the case-only comparison of stored hexadecimal text, and the procedure-level inventory discrepancy for the additional `LINKS_PRESENTATION_RESOURCE_MISSING` code. Neither may be guessed in an implementation PR.

## Implementation stop points

This text specifies exactly the one D13e code named by the supplied gap. Before implementation, resolve the `[PENDING]` hexadecimal-case behavior and reconcile why the reviewer-extracted source also emits `LINKS_PRESENTATION_RESOURCE_MISSING` while the authoritative 30-code gap omits it. No predicate is derived from either issue-code name.
