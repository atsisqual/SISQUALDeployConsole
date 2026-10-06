# Phase 3 runtime catalog factory - superseded evidence

**Status:** [CONFIRMED] superseded
**Date:** 2026-10-06

Run `37402464400` (run #4, commit `1c8316a47d9d61fef4a427834d3b6f87c7e6ca7a`) was the first complete 25/25 PASS on Windows Server 2022 and 2025 and remains valid historical evidence for that implementation.

It is no longer the accepted final evidence for PR #54 because the subsequent Codex review identified additional package-path hardening requirements: reject relative package roots, reject mapped network drives, compare the provider version exactly, and close the reparse/replacement race around provider/catalog open.

Those changes were implemented and revalidated. The accepted evidence is now run `37404050977` (run #10) under:

`docs/phase3/evidence/runtime-catalog-37404050977/`

The original run #4 artifact IDs/digests and 25-check reports remain versioned in this directory for audit history. They must not be deleted or reclassified as a failure.
