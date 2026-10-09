# DEPLOYMENT_PREFLIGHT audit: Web Access model

**Status:** [PROPOSED]
**Original:** `cfg.ReviewWebAccessModel`
**Engine:** `Invoke-ReviewWebAccess`
**Evidence:** `main@f7989a6b9043b9b16300404eb7e1dd27ca06a2aa` and PR #67 branch `engine/deployment-preflight-v1`.

## Audit

| Code | Original predicate, textual | Engine behavior | Coincidem? | T-SQL semantics / port rule |
|---|---|---|---|---|
| `WEB_ACCESS_POLICY_MISSING` | Enabled local `dbo.ManagedServer` where `MachineName=@MachineName` and no enabled `cfg.WebAccessPolicy` with `P.ServerCode=S.ServerCode`. | Engine asks `Get-ServerPolicyRows 'cfg_WebAccessPolicy' $Context.Server` and emits when count is zero. | **Same intent, portable scope differs.** Runtime already resolves the local server; source repeats machine equality. | Legacy MachineName/ServerCode equality is CI_AS/padded; portable server code is exact and Windows machine matching is handled before review. |
| `WEB_ACCESS_USERNAME_MISSING` | Enabled local instance, optional selected code, `NULLIF(I.WebAccessUserName,N'') IS NULL`. | Selected instances only; `IsNullOrWhiteSpace(WebAccessUserName)`. | **No at whitespace boundary.** | SQL padded equality makes empty/ordinary-spaces-only missing; tab-only is nonempty. Engine treats tabs/all whitespace as missing. InstanceCode source equality is CI_AS/padded; portable code exact. |
| `WEB_ACCESS_PASSWORD_MISSING` | Same local/optional selected scope; `NULLIF(I.WebAccessPassword,N'') IS NULL`. | Selected instance lacks request secret `WEB_ACCESS.<InstanceCode>`. | **Architecture-equivalent intent, not literal.** | Legacy spaces-only `nvarchar` counts empty; portable secret is opaque credential-package data and presence is not a database collation comparison. |
| `WEB_ACCESS_BACKEND_URL_MISSING` | Local enabled instance joined to enabled policy; `NULLIF(cfg.ExpandTemplate(I.InstanceCode,P.BackendBaseUrlTemplate),N'') IS NULL`. | Engine iterates server policy rows and tests raw `BackendBaseUrlTemplate` with `IsNullOrWhiteSpace`; no per-instance expansion. | **No.** A nonblank template that expands to empty can be missed; broad whitespace differs too. | Original `NULLIF` uses SQL padding after expansion. Template expansion is part of the original predicate and cannot be replaced by raw-field presence. |
| `WEB_ACCESS_PUBLIC_URL_MISSING` | Same as backend but `cfg.ExpandTemplate(...,P.PublicLaunchBaseUrlTemplate)`. | Raw policy `PublicLaunchBaseUrlTemplate` checked with `IsNullOrWhiteSpace`. | **No.** Same expansion and whitespace differences. | Same padded-empty semantics after expansion. |
| `WEB_ACCESS_DUPLICATE_LOCAL_USER` | Enabled local instances in optional selected scope; `GROUP BY I.ServerCode,I.WebAccessUserName HAVING COUNT(*)>1`; reports `MIN(I.InstanceCode)`. | Rule 6: groups **all enabled machine instances** by case-insensitive username and emits on each selected holder of a duplicated user. | **Intentional scope/reporting change plus text-boundary difference.** | Original grouping is CI_AS/padded: case-only and trailing-space-only usernames group; accent variants differ. Engine ignore-case map does not inherently apply SQL trailing-space padding. Rule 6 intentionally broadens selected-instance runs. |
| `WEB_ACCESS_TEMPLATE_MISSING` | `NOT EXISTS` enabled `cfg.WebAccessTemplate` where `TemplateCode='ROOT_DEFAULT_ASPX'` and `NULLIF(ContentTemplate,N'') IS NOT NULL`. | Engine emits only when **no enabled WebAccessTemplate row at all** exists. | **No.** An unrelated enabled template suppresses the engine issue; original requires the exact named template and substantive content. | `TemplateCode` legacy comparison is CI_AS/padded but portable catalog code is exact. `NULLIF(ContentTemplate,'')` treats ordinary-spaces-only as empty, tab-only as nonempty. |

## Result

Only policy presence has near-equivalent intent. Username/password checks differ at credential/whitespace boundaries; duplicate-user scope is deliberately broadened by rule 6; both URL predicates omit original per-instance expansion; and the template predicate is materially broader in the engine. This audit is text only and does not authorize changes to PR #67.
