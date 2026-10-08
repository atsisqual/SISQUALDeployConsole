# EngineHost conformance kit

This directory contains the fake engine and Windows CI tests for ADR-0008. The fake engine is test-only and is never packaged as a production engine.

The matrix covers process isolation, catalog SourceFileName resolution, manifest hash verification, request/result limits, stdout and stderr capture, secret scanning (plain, base64 and URL-encoded), schema arithmetic, preview/apply fingerprint continuity, cancellation, timeout behavior, and aggregate composite fingerprints, catalog-machine ownership from an active verified runtime-catalog session, deadline-bounded redirected-stream draining, and invalid UTF-8 result rejection.

`Test-EngineHostMutations.ps1` deliberately mutates catalog/manifest/result inputs to prove that fail-closed guards are effective.

## Final ADR-0008 review boundaries

- Machine ownership is not caller input. The host accepts an active runtime-catalog session and reads exactly one `dbo_ManagedServer.MachineName` through that session.
- Redirected stdout and stderr completion is bounded by the engine deadline. Orphan descendants are cleaned up and cannot hold the host indefinitely.
- Result files are strict UTF-8. Invalid byte sequences are audited as `ENGINE_INVALID_RESULT`.
- The runtime-catalog integration test exercises the ownership reader against the actual `Microsoft.Data.Sqlite` provider; EngineHost unit tests use only the isolated test session stub.
