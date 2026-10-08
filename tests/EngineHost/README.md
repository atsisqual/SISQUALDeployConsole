# EngineHost conformance kit

This directory contains the fake engine and Windows CI tests for ADR-0008. The fake engine is test-only and is never packaged as a production engine.

The matrix covers process isolation, catalog SourceFileName resolution, manifest hash verification, request/result limits, stdout and stderr capture, secret scanning (plain, base64 and URL-encoded), schema arithmetic, preview/apply fingerprint continuity, cancellation, timeout behavior, and aggregate composite fingerprints, catalog-machine ownership from an active verified runtime-catalog session, deadline-bounded redirected-stream draining, and invalid UTF-8 result rejection.

`Test-EngineHostMutations.ps1` deliberately mutates catalog/manifest/result inputs to prove that fail-closed guards are effective.
