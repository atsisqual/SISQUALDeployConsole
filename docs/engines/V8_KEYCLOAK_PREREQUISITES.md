# Engine port specification: V8_KEYCLOAK_PREREQUISITES

**Status:** [PROPOSED] specification for review (task 3, wave 4). No product code.
**Date:** 2026-10-05
**Sources (read only):** `ops.Engine` row `V8_KEYCLOAK_PREREQUISITES` of `database/sync/ManagementSync.sql` of `atsisqual/SISQUALManagementConsole` (file `V8_KEYCLOAK_PREREQUISITES.ps1`, version `v7`, Windows PowerShell 5.1, requires administrator, stored `ScriptSha256` `1FBB9B65...`; reference head `9756ba956842884fabcf25b82c4fbf1d11cf56bd`); the action `V8_KEYCLOAK_PREREQUISITES`; step 12 of `FULL_DEPLOYMENT`. Script text is not copied and no secret value appears here.
Tags: [CONFIRMED] read in the source; [PROPOSED] recommendation; [PENDING] needs a decision; [V] needs a real server.

## 1. Purpose

Make sure the three things the V8 Keycloak service needs exist on the machine: the NSSM service wrapper, JDK 23, and the SQL Server integrated-authentication library for JDBC. [CONFIRMED] Action: group `INFRASTRUCTURE`, preview and apply, no instance selection, step 12 of `FULL_DEPLOYMENT` (stop on error). It is machine-wide, not per instance.

## 2. Inputs

[CONFIRMED] **Nothing comes from the catalog**: everything is fixed in the script. Parameters for instance, rule, group and backup root are accepted and ignored.

| Item | Present when | Installed from |
|---|---|---|
| NSSM | the wrapper executable exists at its fixed path under the system drive | an archive named for NSSM in the installer folder: expanded to the temporary folder, the 64-bit executable copied |
| JDK 23 | a folder named for JDK 23 exists under the Java program folder | an installer for JDK 23 (Windows x64) in the installer folder, run silently and waited for |
| JDBC integrated-authentication library (version 12.8.1, x64) | the library file exists in the system directory | a file with that name pattern in the installer folder, copied into the system directory |

The installer folder is found by trying three fixed drive-letter paths of the old console's `_Install` folder, `deployment-installers` subfolder.

## 3. Steps

For each item: if present, `OK`; otherwise look for the source in the installer folder: not found is `MISSING`, found is installed and reported `INSTALLED`. Print the table; if any item is `MISSING`, fail naming the items.

## 4. Side effects

Writes the NSSM folder, runs a JDK installer (system-wide installation), copies a library **into the Windows system directory**, and leaves an extracted archive in the temporary folder.

## 5. External dependencies

An installer folder with three files; the JDK installer's silent switches; administrator rights.

## 6. Preview and apply

[CONFIRMED, defect] The script never reads `-Apply`: **it installs even when only a preview is requested**, while the action is marked preview and apply. [PROPOSED] A real preview that lists each item as `OK`, `WOULD_INSTALL` or `MISSING_SOURCE` and installs nothing; apply installs.

## 7. Idempotency

Present items are left alone. [PROPOSED] Presence is judged by version and hash, not by a folder name pattern: a half-installed or different JDK 23 folder is reported.

## 8. Failures

A missing source is reported with its expected name; an installer that fails (exit code, which the old code ignores) is an error; a hash or signature mismatch (section 10) refuses to run it; a failure stops the engine before later items.

## 9. Backup and restore

An installation is not undone. [PROPOSED] Record in the result what was installed and from which verified file; replacing a library in the system directory first copies the previous one to the backup root. Uninstalling is out of scope.

## 10. Secret risks

No secrets. The risk is supply chain: the old code runs an installer elevated without checking its hash or signature, and copies a library into the system directory. [PROPOSED] Pin each source by SHA-256 (and check the publisher signature of the JDK installer); refuse anything not pinned; log names and hashes.

## 11. What does not port as it is

The fixed drive-letter search of the old console's folder disappears: that folder will not exist. [PROPOSED] A small prerequisite model in the catalog (item, kind, source file name, SHA-256, target path, version check) and an operator-given installer folder; the installers are too large for the portable folder and are not part of the manifest.

## 12. Test plan

- Runner: fake installers (a script that creates the target); item present, missing source, hash mismatch, install success and failure, **a preview that changes nothing** (regression test for the defect), a second run with everything present, the temporary folder cleaned, a backup of a replaced library.
- [V] The real JDK, NSSM and library on a clean server; the silent-install switches of the chosen JDK build.

## 13. Open questions

1. [PENDING] Where the installers come from and who pins them. Recommendation: an operator-provided folder set in the machine settings, pinned by SHA-256 in the catalog.
2. [PENDING] JDK 23 is a short-term release. Confirm the Keycloak version's requirement and whether to move to a long-term release. Recommendation: decide before porting, since the pin changes.
3. [PENDING] Copying a library into the system directory: is there an alternative (a library path for the service)? Recommendation: test whether the JDBC driver finds it next to the Keycloak files; keep the system directory only if not.

## Host contract

- Engine class: `MUTATING`.
- Credential references: none.
