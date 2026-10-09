# DEPLOYMENT_PREFLIGHT audit: Windows service model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewWindowsServiceModel`
**Engine:** `Invoke-ReviewWindowsServices`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewWindowsServiceModel]
    @MachineName sysname,
    @InstanceCode varchar(20) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ServerCode varchar(30);

    SELECT @ServerCode = S.ServerCode
    FROM dbo.ManagedServer AS S
    WHERE S.MachineName = @MachineName
      AND S.IsEnabled = 1;

    IF @ServerCode IS NULL
    BEGIN
        SELECT
            IssueCode   = CONVERT(varchar(100), 'MANAGED_SERVER_NOT_FOUND'),
            Severity    = CONVERT(varchar(10), 'ERROR'),
            InstanceCode = CONVERT(varchar(20), NULL),
            ServiceCode = CONVERT(varchar(60), NULL),
            Details     = CONVERT(nvarchar(2000), N'No enabled ManagedServer matches the supplied machine.');
        RETURN;
    END;

    DECLARE @Issues table
    (
        IssueCode    varchar(100)    NOT NULL,
        Severity     varchar(10)     NOT NULL,
        InstanceCode varchar(20)     NULL,
        ServiceCode  varchar(60)     NULL,
        Details      nvarchar(2000)  NOT NULL
    );

    IF NOT EXISTS
    (
        SELECT 1
        FROM cfg.WindowsServiceDefinition
        WHERE IsEnabled = 1
    )
    BEGIN
        INSERT INTO @Issues
        VALUES
        (
            'WINDOWS_SERVICE_DEFINITION_MISSING',
            'ERROR',
            NULL,
            NULL,
            N'No enabled cfg.WindowsServiceDefinition row exists.'
        );
    END;

    INSERT INTO @Issues
    (
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    )
    SELECT
        'SERVICE_ACCOUNT_USERNAME_MISSING',
        'ERROR',
        I.InstanceCode,
        D.ServiceCode,
        N'IisIdentityUserName is required because the Windows service uses the per-instance IIS identity.'
    FROM cfg.ManagedInstanceRuntime AS I
    CROSS JOIN cfg.WindowsServiceDefinition AS D
    WHERE I.ServerCode = @ServerCode
      AND I.IsEnabled = 1
      AND D.IsEnabled = 1
      AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
      AND NULLIF(LTRIM(RTRIM(I.IisIdentityUserName)), N'') IS NULL;

    INSERT INTO @Issues
    (
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    )
    SELECT
        'SERVICE_ACCOUNT_PASSWORD_MISSING',
        'ERROR',
        I.InstanceCode,
        D.ServiceCode,
        N'IisIdentityPassword is required to create or reconcile the Windows service logon account.'
    FROM cfg.ManagedInstanceRuntime AS I
    CROSS JOIN cfg.WindowsServiceDefinition AS D
    WHERE I.ServerCode = @ServerCode
      AND I.IsEnabled = 1
      AND D.IsEnabled = 1
      AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
      AND NULLIF(I.IisIdentityPassword, N'') IS NULL;

    INSERT INTO @Issues
    (
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    )
    SELECT
        'SERVICE_NAME_TOO_LONG',
        'ERROR',
        I.InstanceCode,
        D.ServiceCode,
        N'Resolved service name exceeds 256 characters: ' +
            COALESCE(cfg.ExpandTemplate(I.InstanceCode, D.ServiceNameTemplate), N'<NULL>')
    FROM cfg.ManagedInstanceRuntime AS I
    CROSS JOIN cfg.WindowsServiceDefinition AS D
    WHERE I.ServerCode = @ServerCode
      AND I.IsEnabled = 1
      AND D.IsEnabled = 1
      AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
      AND LEN(cfg.ExpandTemplate(I.InstanceCode, D.ServiceNameTemplate)) > 256;

    ;WITH ServiceNames AS
    (
        SELECT
            I.InstanceCode,
            D.ServiceCode,
            ServiceName = cfg.ExpandTemplate(I.InstanceCode, D.ServiceNameTemplate)
        FROM cfg.ManagedInstanceRuntime AS I
        CROSS JOIN cfg.WindowsServiceDefinition AS D
        WHERE I.ServerCode = @ServerCode
          AND I.IsEnabled = 1
          AND D.IsEnabled = 1
          AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
    ), Duplicates AS
    (
        SELECT ServiceName
        FROM ServiceNames
        GROUP BY ServiceName
        HAVING COUNT(*) > 1
    )
    INSERT INTO @Issues
    (
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    )
    SELECT
        'DUPLICATE_SERVICE_NAME',
        'ERROR',
        N.InstanceCode,
        N.ServiceCode,
        N'More than one enabled operation resolves to the same Windows service name: ' + N.ServiceName
    FROM ServiceNames AS N
    INNER JOIN Duplicates AS D
        ON D.ServiceName = N.ServiceName;

    ;WITH IdentityPasswords AS
    (
        SELECT
            IdentityName = LOWER(LTRIM(RTRIM(I.IisIdentityUserName))),
            I.IisIdentityPassword
        FROM cfg.ManagedInstanceRuntime AS I
        WHERE I.ServerCode = @ServerCode
          AND I.IsEnabled = 1
          AND NULLIF(LTRIM(RTRIM(I.IisIdentityUserName)), N'') IS NOT NULL
          AND NULLIF(I.IisIdentityPassword, N'') IS NOT NULL
          AND (@InstanceCode IS NULL OR I.InstanceCode = @InstanceCode)
    )
    INSERT INTO @Issues
    (
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    )
    SELECT
        'SERVICE_IDENTITY_PASSWORD_CONFLICT',
        'ERROR',
        NULL,
        NULL,
        N'The same local service identity has different passwords across enabled instances: ' + IdentityName
    FROM IdentityPasswords
    GROUP BY IdentityName
    HAVING COUNT(DISTINCT IisIdentityPassword) > 1;

    SELECT
        IssueCode,
        Severity,
        InstanceCode,
        ServiceCode,
        Details
    FROM @Issues
    ORDER BY
        CASE Severity WHEN 'ERROR' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
        InstanceCode,
        ServiceCode,
        IssueCode;
END;
```

## Audit

| Original / engine check | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics / port rule |
|---|---|---|---|---|---|
| `MANAGED_SERVER_NOT_FOUND` | Resolve `@ServerCode` from enabled `dbo.ManagedServer` where `MachineName=@MachineName`; if NULL, emit `ERROR` and return. | No check in `Invoke-ReviewWindowsServices`; the portable runtime validates the local server before reviews. | **No engine-code equivalent in this review.** Runtime boundary replaces the source check operationally. | **ARQUITECTURAL** - machine-local runtime resolution is approved; E0h must not reintroduce the central lookup only to recreate this issue row. | Original machine equality is CI_AS/padded. Portable runtime uses Windows-name no-case matching and requires one local server. |
| `WINDOWS_SERVICE_DEFINITION_MISSING` | `IF NOT EXISTS (SELECT 1 FROM cfg.WindowsServiceDefinition WHERE IsEnabled=1)` | Engine loads enabled definitions and emits same code when count is zero. | **Yes in predicate intent.** | - | No text comparison in predicate. |
| `SERVICE_ACCOUNT_USERNAME_MISSING` | `cfg.ManagedInstanceRuntime I CROSS JOIN enabled cfg.WindowsServiceDefinition D ... (@InstanceCode IS NULL OR I.InstanceCode=@InstanceCode) AND NULLIF(LTRIM(RTRIM(I.IisIdentityUserName)),N'') IS NULL` | For each selected instance, engine emits once if `IisIdentityUserName` is `IsNullOrWhiteSpace`; it does not emit one row per enabled service definition. | **No.** Scope is selected-equivalent, but multiplicity differs and engine trims tabs/other whitespace that the original does not. Exact portable instance codes remain approved architecture. | **DIVERGENCIA** - E0h must restore ordinary-space-only trim semantics and original per-definition issue multiplicity while preserving exact `InstanceCode` behavior. | Original LTRIM/RTRIM removes ordinary spaces only; padded `NULLIF` makes spaces-only empty. InstanceCode equality is legacy CI_AS/padded versus exact portable code. |
| `SERVICE_ACCOUNT_PASSWORD_MISSING` | Same selected instance x enabled definition scope, `NULLIF(I.IisIdentityPassword,N'') IS NULL`. | Engine emits once per selected instance when request credential `IIS_IDENTITY.<InstanceCode>` is absent. | **No literal parity.** Credential source is intentionally architectural; per-definition multiplicity is not. | **DIVERGENCIA** - E0h must restore the original per-definition reporting/cardinality while keeping the credential-package source and opaque-secret semantics. | Legacy spaces-only password is empty through SQL padding. Portable secret is opaque bytes/presence, not CI_AS text. |
| `SERVICE_NAME_TOO_LONG` | For selected instance x enabled definition, `LEN(cfg.ExpandTemplate(...)) > 256`. | Engine expands each selected instance/definition and uses `.Length -gt 256`. | **No at trailing-space boundary.** Otherwise same shape. | **DIVERGENCIA** - E0h must emulate SQL `LEN` trailing-space behavior. | SQL `LEN` ignores trailing ordinary spaces; .NET Length counts them. A 256-char substantive name plus trailing spaces can diverge. |
| `DUPLICATE_SERVICE_NAME` | Build `ServiceNames` only for rows passing optional `@InstanceCode`; `GROUP BY ServiceName HAVING COUNT(*)>1`; join duplicate names back to every member row. | Engine deliberately builds names across **all enabled machine instances** under rule 6, groups in a case-insensitive map, and emits on every selected holder of a duplicated name. | **Intentional scope change plus unresolved text/reporting parity.** Rule-6 all-enabled machine scope is approved; SQL padding/reporting are not reproduced fully. | **DIVERGENCIA** - E0h must preserve all-enabled machine scope but add SQL padded grouping parity and reconcile original member/`ServiceCode` reporting. | Original grouping is CI_AS and SQL padded equality: case-only and trailing-space-only names group; accents differ. Engine ignore-case grouping preserves case behavior but not SQL trailing-space padding. |
| `SERVICE_IDENTITY_PASSWORD_CONFLICT` | Selected-scope CTE: `IdentityName=LOWER(LTRIM(RTRIM(I.IisIdentityUserName)))`; nonblank username/password; `GROUP BY IdentityName HAVING COUNT(DISTINCT IisIdentityPassword)>1`. | Engine groups **all enabled** instances by case-insensitive raw username, evaluates groups containing selected members, compares exact credential hashes and emits on selected members. Missing unselected credential emits engine-only `SERVICE_IDENTITY_PASSWORD_UNVERIFIED`. | **No literal parity; architecture and divergence are mixed.** All-enabled comparison and exact package-secret comparison are approved. Username trim/grouping and reporting differ. | **DIVERGENCIA** - E0h must preserve machine-wide rule-6 comparison and exact credential hashes, but restore ordinary-space username normalization/grouping parity and reconcile reporting. | Original username ordinary-space trim + LOWER + CI_AS/padding. Original password DISTINCT is CI_AS text; portable secret hash is intentionally exact. |

## Engine-owned check without original equivalent

| Engine check | Tipo | E0h disposition |
|---|---|---|
| `SERVICE_IDENTITY_PASSWORD_UNVERIFIED` | **ARQUITECTURAL** | Preserve. It is the fail-closed consequence of machine-wide rule 6 plus package credentials: the original could read every database password directly, while the portable engine cannot silently verify an absent external secret. |

## Result

`WINDOWS_SERVICE_DEFINITION_MISSING` is the direct predicate match. `MANAGED_SERVER_NOT_FOUND` is replaced by approved machine-local runtime validation. Credential-package sourcing, machine-wide rule-6 comparison and exact secret semantics are architectural and must remain. The rows marked `DIVERGENCIA` identify E0h work: SQL whitespace/LEN/grouping fidelity, original issue multiplicity/reporting, and username normalization. This audit is text only and does not authorize changes to PR #67.
