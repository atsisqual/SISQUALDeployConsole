# Engine port specification: CONFIG_REPAIR

**Status:** [PROPOSED] specification for review (task 3, wave 2). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `CONFIG_REPAIR` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `Invoke-ConfigRepair.ps1`, version `15.0`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `D37FC5FC...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `CONFIG_REPAIR`; the procedures `cfg.GetRepairPlan` and `cfg.ReviewRepairModel`. Script text is not copied; rules are cited by code only and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Bring the configuration files of the managed applications (JSON, XML, text) to the values the catalog defines, with a preview first and a verification after apply. [CONFIRMED] Action: group `CONFIGURATION`, preview and apply, all enabled instances or one, optional rule and group filters, step 20 of `FULL_DEPLOYMENT` (stop on error).

## 2. Inputs

| Source (catalog) | Content |
|---|---|
| `cfg_ConfigFile` (41 files: JSON 17, XML 21, text 3) | `FileID`, `ApplicationCode`, `RelativePath`, `FileFormat`, `IsRequired`, `IsEnabled` |
| `cfg_ConfigRule` (417 rules, 416 enabled) | `SelectorType` (`JSON_VALUE` 242, `XML_TEXT` 99, `XML_ATTRIBUTE` 37, `XML_NODES_ALL` 29, `TEXT_REGEX` 10), `Selector`, `ExpectedTemplate`, `ValidationType` (`EXACT`, `URL`, `BOOLEAN`, `CONNECTION_STRING`, `PATH`, `INTEGER`), `RepairAction` (all `SET_VALUE`), `RepairValueType` (`STRING` 350, `BOOLEAN` 53, `INTEGER` 14), `RepairGroup` (17 groups), `RepairOrder`, `CreateIfMissing` (128), `MissingParentSelector`, `MissingNodeTemplate`, `AllowEncrypted` (27), `IsSensitive` (55), `CountryCode` (8 country-specific rules) |
| `cfg_ConfigFileRepairPolicy` (8) | `RepairMode` (`PATCH` 7, `REPLACE` 1), `ExpectedContentTemplate` (the whole file for the `REPLACE` one), `NormalizeJsonEscapedAmpersand`, `RepairGroup` |
| `cfg_Application` | `PhysicalPathTemplate` (where the application lives) |
| `dbo_ManagedServer`, `dbo_ManagedInstance` | machine, `ConfigBackupRoot`, and the instance data the templates use |
| credential package | `RULE_SECRET` entries (`credentialRef` = the rule code) for the 16 sensitive rules whose template is a reference `{{secret:RULE:<RuleCode>}}` |

Templates use 9 tokens (`{HOST_NAME}` 150 rules, `{SQL_INSTANCE}` 39, `{CULTURE_CODE}` 23, the Keycloak ports, `{CHANNEL_ID}`, `{DATABASE_NAME}`, `{SQL_INSTANCE_ESCAPED}`). Parameters: instance, rule code, repair group, apply, backup root (default from the catalog).

[CONFIRMED] The 16 secret rules are the client-secret rules (`*_CLIENT_SECRET`, `*_CLIENTSECRET`, 12), `API_V8_API_KEY`, `API_V8_KEYCLOAK_ACCESS_TOKEN`, `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD` and `KEYCLOAK_KEYSTORE_PASSWORD`. In the source each has one literal value for all instances; the converter replaced it by the reference.

## 3. Steps

1. Resolve the machine from the catalog; review the model (three checks in the source: `JSON_VALUE` selectors, the `REPLACE` policies, `XML_TEXT` rules); any error stops.
2. Build the plan: for each enabled instance and each enabled file of its application, the operations of the rules that apply (`PATCH`), or one `REPLACE_FILE` operation, filtered by instance, rule, group and country. Expand each template with the instance data; resolve secret references from the package in memory.
3. Per file: read bytes and detect the encoding (UTF-8 with or without BOM, UTF-16 either order); compute the result in memory with the JSON, XML or text operations; compare.
4. Preview: status `MATCHED`, `WOULD_UPDATE`, `NOT_DEPLOYED` (an optional file that is absent) or `ERROR`, with details. Nothing is written.
5. Apply: for each changed file, back it up once, then write atomically (temporary file in the same folder, then move) keeping the encoding; XML is written without re-indenting and keeps its declaration.
6. Verify: run the same plan in preview mode; any remaining `WOULD_UPDATE` or `ERROR` fails the run.
7. Report: one row per file (instance, application, path, status, details), to the result and the text log.

## 4. Side effects

Rewrites configuration files of the managed applications (administrator rights). Backups and reports under the backup root and the log folder. [CONFIRMED] It does not restart services, application pools or sites. No database writes.

## 5. External dependencies

File system only (existence, locks, antivirus scans), XML and JSON parsers. [CONFIRMED] A file written by an earlier step may be briefly invisible; the old engine retries up to 10 times, 2 s apart.

## 6. Preview and apply

Preview is the default and deterministic: same catalog and files, same list. Apply consumes the fingerprint of the previewed plan (R-032) and refuses if a file or rule changed. [CONFIRMED] The same plan function serves preview, apply and verification, so what was previewed is what is verified.

## 7. Idempotency

A second run reports `MATCHED` for every file. `SET_VALUE` only. [PROPOSED] A rule whose selector finds nothing and `CreateIfMissing` is 0 is an `ERROR` in the file's row (R-017: fail if an expected mutation cannot occur); the old behaviour is to be confirmed by the differential test (question 1). With `CreateIfMissing` the node is created from `MissingNodeTemplate` under `MissingParentSelector`.

## 8. Failures

- A required file that does not exist, a parse error, an unsupported format or an unresolved token or secret reference: `ERROR` for that file, the others continue; the run fails at the end with the count.
- A write failure leaves the original (atomic move); earlier files stay changed and have backups.
- Verification fails: the run fails and lists what remains.
- A locked file (antivirus, application): bounded retry, then `ERROR`.

## 9. Backup and restore

Back up each changed file once per run, to the run folder under its path without the drive letter. [PROPOSED] Keep a run manifest (path, backup path, SHA-256 before and after) and add a restore function that copies back, checks the hash and is tested before the engine is enabled (R-033). The old engine had no restore. Backups contain the old files, which hold real secrets: restrict the folder (administrators only) and set a retention [PENDING].

## 10. Secret risks

- The expected value of a sensitive rule is a secret after resolution. [PROPOSED] Details, logs, results and the report never contain expected or current values of sensitive rules, only the rule code and the kind of change; a marker secret is planted in a test and searched in every artifact.
- Backups and the old files may hold secrets (section 9). The package is read in memory and never written.
- The `REPLACE` content template must be written byte for byte (the conversion once lost the CR of CRLF inside multi-line text; it is fixed and tested), with the encoding of the policy.

## 11. What does not port as it is

The plan, model-review and context procedures disappear with the database: [PROPOSED] a plan builder and a model review as local functions. `cfg.ExpandTemplate` is a SQL function and must be ported with tests before this engine (plan risk C-10); it includes a secret token for the mobile application that this engine does not use. The SQL parameters, the transcript and the old report folders go: text log, result per the engine contract.

## 12. Test plan

- Runner: fixtures for every selector type, validation type and value type; `CreateIfMissing`; `AllowEncrypted`; country-specific rules; the `REPLACE` policy with CRLF, BOM and UTF-16; encoding and XML declaration preservation; no change gives all `MATCHED`; a selector with no match; a malformed file; a locked file; instance, rule and group filters; backup, restore and hash check; the verification pass; a marker secret in every artifact; two instances at once.
- Differential test against the old engine's preview on the same file tree, where a server still has it [V].
- [V] The real trees of a pilot server (41 files per instance), the real rule set, applications reading the changed files.

## 13. Open questions

1. [PENDING] Behaviour for a selector with several matches (`XML_NODES_ALL` is explicit; the others). Recommendation: derive it from the differential test and write it into the spec before porting.
2. [PENDING] Do applications need a restart after a repair? Recommendation: out of scope here (the engine never restarted them); `FULL_DEPLOYMENT` order handles it.
3. [PENDING] Backup retention and the folder ACL. Recommendation: administrators only, keep the last 10 runs, never delete the latest per file.
4. [PENDING] One secret value per rule for all instances is how the data is. Recommendation: keep, and review per-instance secrets when `KEYCLOAK_CLIENT_SECRETS` is specified (wave 4).
5. [PENDING] Bounded retry for just-written files: keep it (recommended), with the limit in the catalog.
