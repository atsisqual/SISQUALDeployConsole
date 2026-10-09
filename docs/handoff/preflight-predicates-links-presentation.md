# DEPLOYMENT_PREFLIGHT predicates: Links presentation resources

**Status:** [PROPOSED]
**Procedure:** `cfg.ReviewLinksPagePresentationResources`
**Verification base:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa`

## Evidence boundary

The predicate source is `docs/handoff/preflight-legacy-procedures.sql.txt`. The requested D13e port set and rules 6 and 7 come from the regenerated `docs/handoff/preflight-port-gap.md` on read-only PR #69.

SQLite table and column names were checked against `tests/Fixtures/carried-schema.json`. `cfg.LinksPagePresentationResource` maps to `cfg_LinksPagePresentationResource`; the carried columns used by the requested predicate are `ResourceCode`, `ResourceText`, `ContentSha256`, and `IsEnabled`.

The corrected inventory fixture exists on PR #67, not main. The regenerated port gap records 66 original codes, 31 implemented and 35 still unported. For this procedure specifically, the original has two codes and exactly one remains unported.

`docs/decisions-log.md` records the source database collation as `Latin1_General_CI_AS`: source text comparison is case-insensitive and accent-sensitive. The same 2026-10-05 owner decision makes catalog codes exact in the new system. `ContentSha256` is hash text, not a catalog code, so the source hash comparison semantics below remain CI_AS.

### Source inventory [CONFIRMED]

The exact extracted procedure emits two issue codes:

- `LINKS_PRESENTATION_RESOURCE_MISSING` -- already implemented by `Invoke-ReviewLinksPresentation` in PR #67: when there is no enabled `cfg_LinksPagePresentationResource` row, the engine emits this `ERROR` code;
- `LINKS_PRESENTATION_HASH_MISMATCH` -- not yet implemented and therefore the single D13e predicate specified below.

The earlier 59-code inventory omitted seven original codes and made this procedure look inconsistent. The corrected 66-code inventory and regenerated `preflight-port-gap.md` resolve that discrepancy; there is no remaining `[PENDING]` inventory question and no 31st-item ambiguity.

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

**Text comparison:** The hash input is not ordinary text equality: SQL Server first executes `CONVERT(varbinary(max), P.ResourceText)` where `ResourceText` is `nvarchar`, then hashes those bytes. The portable test/port must preserve that SQL Server Unicode byte representation rather than silently hashing UTF-8 text; include a non-ASCII text case to prove byte parity. The final `P.ContentSha256 <> LOWER(computed_hex)` uses `Latin1_General_CI_AS`. Therefore stored uppercase and lowercase hexadecimal for the same 64 digest digits compare equal and do **not** trigger. Accent sensitivity is irrelevant to hexadecimal characters.

**Tests:**

- Trigger: an enabled resource has `ResourceText` whose SQL Server-compatible SHA-256 bytes no longer match `ContentSha256`; expect exactly `LINKS_PRESENTATION_HASH_MISMATCH` with `ERROR`.
- Non-trigger: an enabled resource stores the lowercase 64-character SHA-256 of the SQL Server `nvarchar` byte representation of its `ResourceText`; no issue.
- Boundary: use `ResourceText` containing at least one non-ASCII character and verify the portable hash uses the same bytes as `CONVERT(varbinary(max), nvarchar)` rather than UTF-8. Separately, store the same digest in uppercase hexadecimal; this is also a non-trigger under CI_AS.

**Ambiguity:** The predicate shape, carried columns, hash algorithm, enabled-row filter, severity, hash-text case behavior and procedure inventory are now unambiguous.

## Implementation stop points

This text specifies the only code from this procedure that is still unported. `LINKS_PRESENTATION_RESOURCE_MISSING` is already implemented; `LINKS_PRESENTATION_HASH_MISMATCH` remains. No predicate is derived from either issue-code name.
