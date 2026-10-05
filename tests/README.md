# Tests

Test assets are grouped by intent:

- `Unit/` - isolated module behaviour.
- `Contract/` - JSON/schema/API/engine contract validation.
- `Integration/` - portable runtime and local component integration.
- `Static/` - parser, formatting, and static policy checks.
- `Security/` - negative tests for secrets, sessions, CSRF, Host/Origin, paths, and credential packages.
- `Fixtures/` - synthetic non-secret inputs used by tests.

[PROPOSED] Engine ports must add the smallest deterministic test at the appropriate layer before review. Windows-specific behaviour is validated on Windows runners and marked `[V]` until any required real SISQUAL validation is recorded.
