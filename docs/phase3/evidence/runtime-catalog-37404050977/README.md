# Phase 3 runtime catalog factory - superseded evidence

**Status:** [CONFIRMED HISTORICAL - SUPERSEDED]
**Date:** 2026-10-06

This directory preserves the accepted run `37404050977` (#10), commit
`c9905f6a82604073f4c6101f84abd783b8319f7e`, which passed 28/28 on both
Windows Server 2022 and 2025.

It is **not** the final evidence for the current functional runtime.

Run `37404050977` predates later catalog trust hardening, including guarded
provider/catalog byte rebinding, the opaque public catalog session, and the
sealed-catalog sidecar controls.

The accepted functional evidence that supersedes this directory is:

- workflow: `phase3-runtime-catalog`;
- run: `37440720047` (#20);
- tested functional commit: `3fa27ffaf5a92001bb8cd14488a54e9f7a49b034`;
- Windows 2022 job `112193530442`: 34/34 main + 6/6 sidecar checks PASS;
- Windows 2025 job `112193530003`: 34/34 main + 6/6 sidecar checks PASS;
- CI `37440720073` (#190): SUCCESS;
- tools-tests `37440720136` (#90): SUCCESS;
- repository evidence: `docs/phase3/evidence/runtime-catalog-37440720047/`.

## Historical run #10

- workflow id: `375949981`;
- run: `37404050977`;
- run number: `10`;
- exact tested commit: `c9905f6a82604073f4c6101f84abd783b8319f7e`;
- conclusion: `success`.

Windows Server 2022:
- job `112077513923`;
- artifact `11385919117`;
- digest `sha256:7c1801fbe1136946f359540a655ecfe975fd85c67c27d856961ae8f96afedcd8`.

Windows Server 2025:
- job `112077514091`;
- artifact `11386607220`;
- digest `sha256:3a85059e32ed1a6b10bd3a2f163a89b06e8ccb7d384a483a48f881e8570c5596`.

Both reports were 28/28 PASS with PowerShell 7.6.6,
`Microsoft.Data.Sqlite` 10.0.12, native SQLite 3.53.3 and CLI SQLite 3.53.4.

The JSON files in this directory remain valid historical evidence for run #10;
they must not be cited as final evidence for the later runtime implementation.
