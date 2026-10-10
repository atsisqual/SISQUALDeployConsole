# New-server wizard specification

**Status:** [PROPOSED]
**Task:** T18 / M4.4
**Date:** 2026-10-10

This document specifies the V1 new-server wizard. The wizard is a **generator of scripts, manifests and checklists**. It never writes a database, never edits a live catalog in place, never installs software and never performs deployment actions itself.

## 1. Evidence and architecture boundary

[CONFIRMED] Checked now against `main`:

- ADR-0007 removes the runtime management database: each machine receives a read-only verified SQLite catalog and package.
- `Convert-ManagementDb` supports the catalog conversion/new-machine path; validation and sealing are separate tools.
- The roadmap and remaining-work plan explicitly state that the new-server wizard generates scripts/checklists and **never writes to a database**.
- First production acceptance is a server that never had the current Deploy Console; package copy + local startup is the target deployment model.

[NOT VERIFIED] This specification does not prove a complete clean-server deployment. Engine/orchestration clean-server dependencies documented elsewhere remain gates.

## 2. Purpose

Guide an operator from “new Windows server planned” to a reviewable, reproducible set of artifacts/instructions needed to prepare that server and its portable SISQUAL Deploy Console package, without performing those actions from the wizard.

The wizard reduces omission/typing errors; it is not an automation backdoor around owner review, catalog conversion, package sealing or engine confirmations.

## 3. Non-goals

The wizard does **not**:

- create/update SQL Server rows or databases;
- connect to application databases to configure them;
- edit/reseal a production catalog silently;
- issue/decrypt credentials itself;
- install IIS/JDK/NSSM/Keycloak/application files;
- create IIS sites/services/accounts;
- run `FULL_DEPLOYMENT` or any APPLY engine;
- copy customer data/databases;
- bypass package/catalog/machine verification;
- generate unreviewed raw SQL to be pasted into a production database.

## 4. Inputs

[PROPOSED] Wizard inputs are non-secret planning data only, collected through typed fields/selectors:

- new server code/display name;
- expected Windows machine name;
- country/geography where required by the catalog model;
- approved local roots such as ServicesRoot/log/backup/package destinations;
- instances intended for the machine, using exact instance codes and non-secret public/catalog fields required by the new-machine contract;
- source catalog/conversion context selected by the owner where required;
- operator-provided installer folder locations/identities (paths and expected artifact metadata, never credentials);
- feature choices that already exist as approved catalog/policy options.

Secrets/passwords/tokens are not wizard form fields. Credential issuance/import is a separate B6 workflow.

[PENDING] Exact minimal new-machine input schema should be derived from `Convert-ManagementDb` and catalog contracts when M4.4 code begins; this document does not invent columns missing from those contracts.

## 5. Input validation

Before generating anything, validate:

- machine/server/instance code shape and uniqueness;
- no selected instance belongs to two planned machines;
- local roots are fully-qualified local paths and do not use device/UNC syntax unless an approved contract explicitly allows it;
- roots do not overlap in unsafe ways (for example package source inside a generated destructive target);
- planned ports/names supplied by catalog data are not obviously duplicated within the planned machine;
- no field contains a credential/secret payload where only an identifier should exist;
- every selected installer reference has an approved fixed version/hash source in the project contract where required.

Validation errors stop generation; the wizard never “fixes” identifiers by silently normalizing them.

## 6. Output bundle

[PROPOSED] One generated bundle per planned server contains only text/JSON/checklist artifacts such as:

1. `README-FIRST.txt` - ordered operator instructions and prerequisites.
2. `server-plan.json` - canonical non-secret planning input and SHA-256.
3. `01-convert-catalog.ps1` - command wrapper/instructions for the approved `Convert-ManagementDb` new-machine path; it invokes project tooling but contains no SQL mutation statements.
4. `02-validate-catalog.ps1` - command wrapper for `Test-CatalogConversion` / relevant validators.
5. `03-seal-package.ps1` - command wrapper/checklist for package sealing after required content/credentials are prepared by their approved workflows.
6. `04-copy-package.ps1` - safe local copy command/checks for transferring the sealed portable folder to the intended server; no remote execution by default.
7. `05-first-start.txt` - exact `Start.cmd`/preflight acceptance sequence once M1 product commands exist.
8. `credential-checklist.txt` - required credential **reference names/kinds**, issuer/import/issue steps and owner-only handling notes; never values.
9. `installer-checklist.txt` - exact required installer artifact names/versions/hashes and the later engine/operator responsible for installation.
10. `acceptance-checklist.txt` - machine/package/catalog/preflight gates to record before deployment APPLY is considered.

File names are illustrative [PROPOSED]; behavior/safety contract is normative.

## 7. Generated script rules

Every generated PowerShell script:

- starts with strict error handling;
- contains no embedded credentials or secret prompts that echo/store values;
- references repository/product tools by fixed relative path and documented arguments;
- validates expected input files/hashes before invoking a tool;
- uses literal/typed arguments rather than command-string concatenation;
- has a `-WhatIf`/DryRun path where the underlying approved tool supports it;
- stops on non-zero exit and records the exact next manual step;
- never invokes arbitrary text from the catalog as PowerShell/SQL;
- never performs database mutation directly.

The generated wrapper cannot weaken the called tool's verification flags.

## 8. Catalog generation boundary

The wizard may generate the command to create a **new SQLite catalog artifact** through the approved conversion tooling. This is file generation, not a database write to a managed SQL target.

[PROPOSED] It must make the distinction explicit in the UI/output:

- source SQL database: read-only conversion input;
- generated SQLite file: offline artifact under operator workspace;
- production application databases: untouched by the wizard;
- catalog edit after generation: only approved structured owner-edit tooling + validation + seal.

No wizard step opens the generated catalog read-write at runtime.

## 9. Source database access

If conversion requires reading the old management SQL database, the generated instructions state `[V]/owner` prerequisites for connectivity, encryption/certificate policy and permissions. The wizard itself does not open that connection merely to “check” it unless product scope later explicitly adds a **read-only** diagnostic with reviewed security semantics.

A generated conversion command must use the existing tool's structured filters and fail-closed behavior; it does not contain ad-hoc SELECT/UPDATE text.

## 10. Credential workflow boundary

Credentials are owner-controlled outside the catalog/Git.

The wizard may compute/display which reference names will be required by the planned enabled engines/instances, but it never asks for or serializes their values.

[PROPOSED] `credential-checklist.txt` records status categories only: `REQUIRED`, `ISSUE/IMPORT NEEDED`, `VERIFY LATER`. Actual B6.4 package issue/load is executed through approved credential tooling and then verified at startup/preflight.

## 11. Installer workflow boundary

For prerequisites such as exact JDK 23/NSSM/JDBC:

- wizard lists the operator-provided source folder requirement and exact approved hashes/versions;
- wizard does not download “latest” artifacts;
- wizard does not execute installers;
- installation is later performed by the approved prerequisite engine/operator step with its own preview/apply and verification.

## 12. Package assembly/sealing order

[PROPOSED] Generated checklist makes order explicit:

1. freeze/approve source configuration for the cut;
2. generate catalog with approved conversion mode;
3. validate catalog independently;
4. assemble package/runtime/engines/contracts/provider dependencies;
5. issue/include required per-machine credential package through B6 workflow;
6. seal/sign package through approved B5/B6 contracts;
7. record package/catalog/manifest hashes;
8. copy sealed folder to the intended machine;
9. first startup verifies package + machine identity + read-only catalog;
10. run PREVIEW/preflight before any deployment APPLY.

If actual B6/package tooling has a different approved order, code generation follows that merged contract, not this proposed sequence.

## 13. Machine identity

The wizard cannot manufacture/export the non-exportable machine identity. It may explain the Phase 1B bootstrap/enrollment step and verify that the intended machine name matches planning data after startup.

A copied package must not carry another machine's identity. Any mismatch is a startup blocker, not a wizard “repair” option.

## 14. Existing versus new server

This wizard is optimized for a server that never had the Deploy Console/current portable package. It must clearly label any instruction that is unsafe on an existing production machine.

[PROPOSED] Existing-server migration/cutover uses the M5 cutover runbook and explicit owner choice; do not reuse the “new server” bundle as an implicit in-place migration tool.

## 15. Review and reproducibility

Before an operator executes generated steps, the bundle shows:

- generation timestamp and wizard/product version;
- canonical input hash;
- source package/tool versions;
- every unresolved `[PENDING]`/`[V]` gate relevant to the planned server;
- exact files that will be generated/used;
- a diff against a prior wizard bundle when regenerating the same server plan.

Same canonical inputs + same product/tool versions should produce semantically identical commands/checklists except explicitly non-deterministic metadata such as generation timestamp. Prefer deterministic file content and a separate metadata file.

## 16. Failure handling

Generation failure leaves no partially “approved” bundle. Write to a temporary output directory, validate all artifacts, then atomically publish/rename the bundle.

A failed real command later is not automatically rerun by the wizard. The checklist says how to inspect the tool result, fix the condition and re-run the exact operator step.

## 17. Audit and secret safety

Bundle can be retained as project/deployment evidence because it contains no secret values. Before publication, scan generated files for known marker credentials and obvious secret fields.

Paths/machine/instance/customer identifiers may still be operationally sensitive; retention/location follows handover policy even though they are not credential secrets.

## 18. Required tests for wizard implementation

- canonical valid plan generates expected bundle files;
- invalid duplicate instance/machine/path input blocks generation;
- malicious shell metacharacters in display data cannot become executable script text;
- generated scripts parse successfully and use typed/literal arguments;
- no script contains UPDATE/INSERT/DELETE against application/management databases;
- no generated artifact contains supplied marker-secret-like value because wizard never accepts a secret field;
- new-machine conversion wrapper calls only approved conversion tool/options;
- validation/seal/copy wrappers stop on failed predecessor/hash;
- exact installer versions/hashes printed, no dynamic/latest download;
- credential checklist contains reference names only;
- output is deterministic for same inputs after excluding declared metadata;
- atomic output publishing: failed generation leaves previous bundle intact;
- generated first-start/preflight checklist does not include APPLY;
- existing-server input displays cutover warning and does not silently switch modes.

[V] Execute a generated bundle on a clean pilot server as part of M5, recording every deviation between generated instructions and reality.

## 19. Open decisions

1. [PENDING] Exact new-machine planning-input schema and which fields may be entered versus selected from an approved source model.
2. [PENDING] Whether wizard is browser-only, CLI-only or both; generation contract is surface-independent.
3. [PENDING] Whether package assembly is itself a generated wrapper or a product command by M4.
4. [PENDING] Exact retention/location for generated bundles.

## 20. Entry gate for wizard code

Implementation may start when:

- new-machine conversion/package/credential command contracts are merged;
- the operator-interface security model is adopted for any browser surface;
- all generated command targets are versioned local project tools, not ad-hoc shell snippets;
- no database-write capability is required or hidden in “validation”;
- a clean-server acceptance scenario exists to test the generated bundle end to end.
