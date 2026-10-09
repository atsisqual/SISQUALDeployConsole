# DEPLOYMENT_PREFLIGHT audit: Web Access model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewWebAccessModel`
**Engine:** `Invoke-ReviewWebAccess`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

`Tipo` classifies every observable difference: `ARQUITECTURAL` is an approved portable-system difference that E0h must preserve; `DIVERGENCIA` is parity work for E0h. If a row contains both, it is classified `DIVERGENCIA` and the approved sub-difference is called out explicitly.

## Original predicate text

The following block is copied verbatim from `docs/handoff/preflight-legacy-procedures-implemented.sql.txt` on `main`.

```sql
CREATE OR ALTER PROCEDURE [cfg].[ReviewWebAccessModel]
    @MachineName sysname = NULL,
    @InstanceCode varchar(20) = NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;

    SET @MachineName =
        COALESCE
        (
            NULLIF(@MachineName, N''),
            CONVERT(sysname, SERVERPROPERTY('MachineName'))
        );

    SET @InstanceCode = NULLIF(@InstanceCode, '');

    DECLARE @Issues TABLE
    (
        IssueCode   varchar(100)   NOT NULL,
        Severity    varchar(10)    NOT NULL,
        InstanceCode varchar(20)   NULL,
        Details     nvarchar(2000) NOT NULL
    );

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_POLICY_MISSING',
        'ERROR',
        NULL,
        N'The enabled ManagedServer has no enabled Web Access policy.'
    FROM dbo.ManagedServer AS S
    WHERE S.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND NOT EXISTS
      (
          SELECT 1
          FROM cfg.WebAccessPolicy AS P
          WHERE P.ServerCode = S.ServerCode
            AND P.IsEnabled = 1
      );

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_USERNAME_MISSING',
        'ERROR',
        I.InstanceCode,
        N'WebAccessUserName is empty.'
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
    WHERE S.IsEnabled = 1
      AND I.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND
      (
          @InstanceCode IS NULL
          OR I.InstanceCode = @InstanceCode
      )
      AND NULLIF(I.WebAccessUserName, N'') IS NULL;

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_PASSWORD_MISSING',
        'ERROR',
        I.InstanceCode,
        N'WebAccessPassword is empty. Store the per-instance password before deployment.'
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
    WHERE S.IsEnabled = 1
      AND I.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND
      (
          @InstanceCode IS NULL
          OR I.InstanceCode = @InstanceCode
      )
      AND NULLIF(I.WebAccessPassword, N'') IS NULL;

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_BACKEND_URL_MISSING',
        'ERROR',
        I.InstanceCode,
        N'Web Access backend URL cannot be resolved from cfg.WebAccessPolicy.'
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
    INNER JOIN cfg.WebAccessPolicy AS P
        ON P.ServerCode = I.ServerCode
       AND P.IsEnabled = 1
    WHERE S.IsEnabled = 1
      AND I.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND
      (
          @InstanceCode IS NULL
          OR I.InstanceCode = @InstanceCode
      )
      AND NULLIF
      (
          cfg.ExpandTemplate
          (
              I.InstanceCode,
              P.BackendBaseUrlTemplate
          ),
          N''
      ) IS NULL;

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_PUBLIC_URL_MISSING',
        'ERROR',
        I.InstanceCode,
        N'Web Access public launch URL cannot be resolved from cfg.WebAccessPolicy.'
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
    INNER JOIN cfg.WebAccessPolicy AS P
        ON P.ServerCode = I.ServerCode
       AND P.IsEnabled = 1
    WHERE S.IsEnabled = 1
      AND I.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND
      (
          @InstanceCode IS NULL
          OR I.InstanceCode = @InstanceCode
      )
      AND NULLIF
      (
          cfg.ExpandTemplate
          (
              I.InstanceCode,
              P.PublicLaunchBaseUrlTemplate
          ),
          N''
      ) IS NULL;

    INSERT INTO @Issues
    SELECT
        'WEB_ACCESS_DUPLICATE_LOCAL_USER',
        'ERROR',
        MIN(I.InstanceCode),
        N'The local Web Access username is assigned to more than one enabled instance on the same server: ' +
        I.WebAccessUserName
    FROM dbo.ManagedServer AS S
    INNER JOIN cfg.ManagedInstanceRuntime AS I
        ON I.ServerCode = S.ServerCode
    WHERE S.IsEnabled = 1
      AND I.IsEnabled = 1
      AND S.MachineName = @MachineName
      AND
      (
          @InstanceCode IS NULL
          OR I.InstanceCode = @InstanceCode
      )
    GROUP BY
        I.ServerCode,
        I.WebAccessUserName
    HAVING COUNT(*) > 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM cfg.WebAccessTemplate
        WHERE TemplateCode = 'ROOT_DEFAULT_ASPX'
          AND IsEnabled = 1
          AND NULLIF(ContentTemplate, N'') IS NOT NULL
    )
    BEGIN
        INSERT INTO @Issues
        VALUES
        (
            'WEB_ACCESS_TEMPLATE_MISSING',
            'ERROR',
            NULL,
            N'The enabled ROOT_DEFAULT_ASPX template is missing.'
        );
    END;

    SELECT
        IssueCode,
        Severity,
        InstanceCode,
        Details
    FROM @Issues
    ORDER BY
        CASE Severity
            WHEN 'ERROR' THEN 1
            WHEN 'WARNING' THEN 2
            ELSE 3
        END,
        IssueCode,
        InstanceCode;
END;
```

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | Tipo | T-SQL semantics / port rule |
|---|---|---|---|---|---|
| `WEB_ACCESS_POLICY_MISSING` | Enabled local `dbo.ManagedServer` where `MachineName=@MachineName` and no enabled `cfg.WebAccessPolicy` with `P.ServerCode=S.ServerCode`. | Engine asks `Get-ServerPolicyRows 'cfg_WebAccessPolicy' $Context.Server` and emits when count is zero. | **Same intent, portable scope differs.** Runtime already resolves the local server; source repeats machine equality. | **ARQUITECTURAL** - machine-local runtime/catalog scope and exact `ServerCode` behavior are approved; E0h must preserve them. | Legacy MachineName/ServerCode equality is CI_AS/padded; portable server code is exact and Windows machine matching is handled before review. |
| `WEB_ACCESS_USERNAME_MISSING` | Enabled local instance, optional selected code, `NULLIF(I.WebAccessUserName,N'') IS NULL`. | Selected instances only; `IsNullOrWhiteSpace(WebAccessUserName)`. | **No at whitespace boundary.** | **DIVERGENCIA** - E0h must reproduce SQL empty/ordinary-space semantics while retaining exact portable `InstanceCode` handling and machine-local scope. | SQL padded equality makes empty/ordinary-spaces-only missing; tab-only is nonempty. Engine treats tabs/all whitespace as missing. InstanceCode source equality is CI_AS/padded; portable code exact. |
| `WEB_ACCESS_PASSWORD_MISSING` | Same local/optional selected scope; `NULLIF(I.WebAccessPassword,N'') IS NULL`. | Selected instance lacks request secret `WEB_ACCESS.<InstanceCode>`. | **Architecture-equivalent intent, not literal.** Password source moved from database text to external credential package. | **ARQUITECTURAL** - preserve package-secret presence and opaque secret semantics; E0h must not recreate a catalog password field or CI_AS secret comparison. | Legacy spaces-only `nvarchar` counts empty; portable secret is opaque credential-package data and presence is not a database collation comparison. |
| `WEB_ACCESS_BACKEND_URL_MISSING` | Local enabled instance joined to enabled policy; `NULLIF(cfg.ExpandTemplate(I.InstanceCode,P.BackendBaseUrlTemplate),N'') IS NULL`. | Engine iterates server policy rows and tests raw `BackendBaseUrlTemplate` with `IsNullOrWhiteSpace`; no per-instance expansion. | **No.** A nonblank template that expands to empty can be missed; broad whitespace differs too. | **DIVERGENCIA** - E0h must evaluate the expanded per-instance value and preserve SQL ordinary-space empty semantics. | Original `NULLIF` uses SQL padding after expansion. Template expansion is part of the original predicate and cannot be replaced by raw-field presence. |
| `WEB_ACCESS_PUBLIC_URL_MISSING` | Same as backend but `cfg.ExpandTemplate(...,P.PublicLaunchBaseUrlTemplate)`. | Raw policy `PublicLaunchBaseUrlTemplate` checked with `IsNullOrWhiteSpace`. | **No.** Same expansion and whitespace differences. | **DIVERGENCIA** - E0h must evaluate the expanded per-instance value and preserve SQL ordinary-space empty semantics. | Same padded-empty semantics after expansion. |
| `WEB_ACCESS_DUPLICATE_LOCAL_USER` | Enabled local instances in optional selected scope; `GROUP BY I.ServerCode,I.WebAccessUserName HAVING COUNT(*)>1`; reports `MIN(I.InstanceCode)`. | Rule 6 groups **all enabled machine instances** by case-insensitive username and emits on each selected holder of a duplicated user. | **Intentional scope change plus text/reporting divergence.** Machine-wide comparison is approved; SQL padding and reporting are not reproduced exactly. | **DIVERGENCIA** - E0h must preserve machine-wide rule-6 scope but add padded grouping parity and reconcile `MIN(InstanceCode)`/selected-holder reporting. | Original grouping is CI_AS/padded: case-only and trailing-space-only usernames group; accent variants differ. Engine ignore-case map does not inherently apply SQL trailing-space padding. |
| `WEB_ACCESS_TEMPLATE_MISSING` | `NOT EXISTS` enabled `cfg.WebAccessTemplate` where `TemplateCode='ROOT_DEFAULT_ASPX'` and `NULLIF(ContentTemplate,N'') IS NOT NULL`. | Engine emits only when **no enabled WebAccessTemplate row at all** exists. | **No.** An unrelated enabled template suppresses the engine issue; original requires the exact named template and substantive content. | **DIVERGENCIA** - E0h must require `ROOT_DEFAULT_ASPX` and its original content predicate while preserving exact portable `TemplateCode` comparison. | `TemplateCode` legacy comparison is CI_AS/padded but portable catalog code is exact. `NULLIF(ContentTemplate,'')` treats ordinary-spaces-only as empty, tab-only as nonempty. |

## Result

Policy presence and password sourcing differ only through approved machine-local/exact-code/credential-package architecture. Username whitespace, both URL expansion checks, duplicate-user SQL grouping/reporting and the exact template/content requirement are `DIVERGENCIA` work for E0h. E0h must correct those without undoing package credentials, machine-local scope, rule-6 machine-wide conflict detection or exact catalog codes. This audit is text only and does not authorize changes to PR #67.
