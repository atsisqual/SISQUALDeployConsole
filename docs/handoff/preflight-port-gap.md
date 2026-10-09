# DEPLOYMENT_PREFLIGHT: issue codes of the original reviews not ported yet

**Status:** [CONFIRMED] measured from `tests/Fixtures/preflight-legacy-codes.json` (read from the original review procedures of `ManagementSync.sql`) and `engines/Invoke-DeploymentPreflight.ps1` of PR #67. Owner decision A (2026-10-09): the engine is integrated as an incomplete first slice and the remaining codes are ported in follow-up pull requests.

The original reviews have 59 issue codes. The engine implements 29. 30 are not ported yet. `Test-DeploymentPreflightSchema.ps1` prints this same list in CI (`DIAG  not yet ported from ...`) and fails if the engine declares more coverage than it has.

## How to port one review

1. The predicate is the stored procedure named in the heading, in the reference snapshot (`database/sync/ManagementSync.sql`). Port the SQL condition exactly; do not infer it from the code name.
2. Keep the severity of the original (the test compares it). An owner decision overrides it only if it is in `ownerSeverityOverrides` of the fixture.
3. One test per code, with data in the synthetic catalog that makes the code fire and data that does not (the synthetic catalog must use real columns: `Test-DeploymentPreflightSchema.ps1` checks it).
4. Raise `$script:CoverageImplemented` in the engine by the number of codes you add (the test checks it against the source).
5. Read `docs/engines/porting-guide.md` first. Do not edit the host or the contracts.
6. **Cross-instance rule (it cost five Codex rounds on the first slice).** FULL_DEPLOYMENT calls the preflight for one instance at a time. A check that says two things must differ (a port, a pool name, a site name, a user, a service name, a path, an account with one password) is evaluated against EVERY enabled instance of the machine (`$Context.Instances | Where-Object { Test-Enabled $_ }`), and the issue is reported on the SELECTED instance that takes part in it (`Add-Issue ... $selectedInstanceCode`). Iterating `$Context.SelectedInstances` for the comparison is the defect. The credentials of the other instances come in the request, never from the catalog; if they are needed and missing the result is an ERROR, not silence. Test it with a run for one instance whose conflict is with an instance that is not selected.
7. **Containment rule.** A path that comes from the catalog is resolved (junctions and symbolic links followed, `Resolve-RealPath`) and must stay under its approved root (`Test-RealPathUnderRoot`) before it is probed. A path that cannot be read is an ERROR for that item, never an exception. Windows names (accounts, services, users) are compared without case; catalog codes exactly.
8. Check every new rule against the six real converted catalogs before you push, and say in the pull request how many false positives it gives (the reviewer has them; ask for the query result if you cannot run it).

Map each procedure to the review name of `docs/engines/DEPLOYMENT_PREFLIGHT.md` before you start; the procedure name is the authority for the predicate, the review name is the label.

## cfg.ReviewExtendedApplicationModel (10 of 10 not ported)

| Code | Original severity |
|---|---|
| `AUTO_START_APPLICATION_PROVIDER_NOT_EXPANDED` | ERROR |
| `AUTO_START_ASSEMBLY_LOADABILITY` | WARNING |
| `AUTO_START_POOL_NOT_ALWAYS_RUNNING` | ERROR |
| `AUTO_START_PROVIDER_EXPANDED_NAME_DUPLICATE` | ERROR |
| `AUTO_START_PROVIDER_EXPANDED_NAME_INVALID` | ERROR |
| `AUTO_START_PROVIDER_NOT_ENABLED` | ERROR |
| `AUTO_START_PROVIDER_TEMPLATE_MISSING` | ERROR |
| `AUTO_START_PROVIDER_TYPE_MISSING` | ERROR |
| `PROCESS_HANGFIRE_RULE_MISSING` | ERROR |
| `PROCESS_OWIN_RULE_MISSING` | ERROR |

## cfg.ReviewIisDeploymentModel (7 of 9 not ported)

| Code | Original severity |
|---|---|
| `CERTIFICATE_POLICY_MISSING` | ERROR |
| `DUPLICATE_POOL_TEMPLATE` | ERROR |
| `IIS_IDENTITY_PASSWORD_CONFLICT` | ERROR |
| `PRIMARY_BINDING_COUNT` | ERROR |
| `ROOT_DEFINITION_COUNT` | ERROR |
| `ROOT_POOL_NAME_INVALID` | ERROR |
| `SERVER_NOT_REGISTERED` | ERROR |

## cfg.ReviewLinksPageModel (7 of 8 not ported)

| Code | Original severity |
|---|---|
| `LINKS_BRAND_LOGO_MISSING` | ERROR |
| `LINKS_INDEX_TEMPLATE_MISSING` | ERROR |
| `LINKS_WEB_CONFIG_TEMPLATE_MISSING` | ERROR |
| `MANAGED_INSTANCE_NOT_ACTIONABLE` | ERROR |
| `MANAGED_SERVER_NOT_FOUND` | ERROR |
| `NO_PUBLISHED_LINK_APPLICATIONS` | ERROR |
| `PUBLISHED_APPLICATION_URL_UNRESOLVED` | ERROR |

## cfg.ReviewLinksPagePresentationResources (1 of 1 not ported)

| Code | Original severity |
|---|---|
| `LINKS_PRESENTATION_HASH_MISMATCH` | ERROR |

## cfg.ReviewWebsiteBrandingModel (5 of 5 not ported)

| Code | Original severity |
|---|---|
| `WEBSITE_BRANDING_ASSET_HASH_MISMATCH` | ERROR |
| `WEBSITE_BRANDING_PROFILE_MISSING` | ERROR |
| `WEBSITE_BRANDING_REQUIRED_ASSET_MISSING` | ERROR |
| `WEBSITE_BRANDING_ROOT_MISSING` | ERROR |
| `WEBSITE_BRANDING_TITLE_INVALID` | ERROR |

## Reviews that are complete in the engine

`cfg.ReviewLinksPageQrCodes` (3 codes), `cfg.ReviewPulseModel` (6 codes), `cfg.ReviewWebAccessModel` (7 codes), `cfg.ReviewWindowsServiceModel` (6 codes), `ops.ReviewOperationsFramework` (4 codes).
