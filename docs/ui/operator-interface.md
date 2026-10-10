# Operator interface specification

**Status:** [PROPOSED]
**Task:** T17 / M4.1
**Date:** 2026-10-10

This document specifies the local browser/operator surface. It is text only; it does not select a front-end framework or add product code.

## 1. Evidence and constraints

[CONFIRMED] Checked now against `main`:

- ADR-0001/Phase 1A define a portable interactive process reached on loopback.
- `docs/phase1/phase1c-local-web-security.md` validated the corrected V2 local-web boundary on Windows Server 2022/2025: loopback only, one-time fragment bootstrap, explicit in-memory `X-SISQUAL-Session`, explicit `X-SISQUAL-CSRF` for mutations, exact Host/Origin, no CORS, restrictive browser headers, no session cookie or browser storage.
- `docs/phase1/phase1c-operation-coordinator.md` validated operation identity, idempotency, locks, cooperative cancellation and shutdown that refuses to exit while unsafe active work remains.
- The remaining-work plan requires the UI to expose confirmations before APPLY and to consume the engine/orchestrator contracts rather than execute arbitrary text.

[NOT VERIFIED] The real vanilla-JS fragment-to-header flow has not yet been adopted/proven in product code. This specification does not claim that Phase 1C spike adoption is complete.

## 2. Operator model

[CONFIRMED] V1 is single-operator and local-only. The UI is an administrative surface, not a multi-user web application and not a remotely served console.

[PROPOSED] The browser opens only the listener launched by the same portable process. The UI cannot change listener address/port policy, weaken Host/Origin/TLS rules, or expose a remote bind option.

## 3. Security boundary in the browser

The UI must implement the accepted V2 candidate exactly unless a later decision supersedes it:

1. process launches browser with one-time bootstrap token in URL **fragment**, never query;
2. JavaScript sends it once as `X-SISQUAL-Bootstrap` and immediately clears the fragment using `history.replaceState`;
3. bootstrap response returns independent session and CSRF values;
4. session/CSRF live only in JavaScript memory;
5. every protected API call sends `X-SISQUAL-Session`;
6. every mutation also sends `X-SISQUAL-CSRF`; browser supplies exact local Origin;
7. no session cookie, localStorage or sessionStorage copy;
8. logout discards memory values and invalidates them server-side;
9. process restart invalidates the session;
10. UI never writes bootstrap/session/CSRF values to DOM text, URL, console, telemetry or error details.

A reload after bootstrap state is gone may require a new launch/bootstrap; the UI must prefer re-authentication over persistence of the local credential.

## 4. Information architecture

V1 has these operator surfaces:

1. **Startup status** - package/catalog/machine verification state and why startup is blocked, if blocked.
2. **Machine overview** - verified machine identity, catalog provenance/build time, selected package version and enabled-instance count.
3. **Instances** - enabled local instances and non-secret state needed to choose a target.
4. **Actions** - enabled supported actions grouped by purpose/class; composite and engine actions are visually distinct.
5. **Action preview** - parameters/target, child or engine plan rows, warnings/errors, disruptive effects, credential-reference names, backup capability and fingerprint.
6. **Apply confirmation** - exact immutable preview being confirmed and required confirmation text.
7. **Operation** - current/terminal operation status, target/step/result summaries, cancellation state and log reference.
8. **Result detail** - structured result rows with filtering, not raw engine stdout/stderr.
9. **Recovery/evidence** - backup/run-manifest references and restore availability, without exposing protected contents.
10. **Shutdown** - safe exit status and active operation(s) preventing exit.

No arbitrary SQL/script/file editor belongs in this surface.

## 5. Startup status

Before normal navigation, show one of:

- `READY`: package signature/integrity, machine identity and catalog checks completed;
- `BLOCKED`: fail-closed reason code and safe operator guidance;
- `STARTING`: bounded initialization in progress.

[PROPOSED] A blocked startup page exposes only non-secret reason categories and evidence references. It never offers “continue anyway”, “ignore hash”, “trust this catalog”, or direct editing of manifest/catalog files.

## 6. Machine overview

Display:

- local machine/server code after verified resolution;
- package/manifest identity and verification state;
- catalog schema/cut-rule version, build/provenance time and catalog SHA-256 in copyable form;
- enabled instance count;
- latest operation status;
- explicit `[V]`/acceptance warning when product/engine gates documented as not validated on a real server still apply.

Do not display credential counts as values that imply secrets were decrypted; if package readiness is shown, use presence/verification summaries only.

## 7. Instance selection

[PROPOSED] Instance picker contains only enabled instances from the verified local catalog and uses exact instance codes. Disabled/remote directory rows never become executable targets.

Machine-scoped actions hide the instance picker. Actions allowing optional single-instance scope offer `All enabled instances` plus exact local choices. UI cannot submit a free-form instance code.

## 8. Action catalogue

Each action card displays data from the verified action/engine registry:

- action code/display name/group;
- `ENGINE` versus `COMPOSITE`;
- class where applicable (`READ_ONLY`, `OBSERVATIONAL`, `MUTATING`);
- supported mode(s);
- target scope;
- high-level disruptive marker (restart/outage/destructive) from approved metadata/specification;
- availability/blocked reason.

[PROPOSED] An action not supported by the local registry/package is not rendered as runnable. The UI never turns a catalog action/engine code into executable script text.

## 9. Parameter entry

Use typed controls defined by the action contract:

- exact instance selector;
- enum/radio/check controls for bounded choices;
- validated local file/folder selection only where a product contract explicitly permits operator paths;
- no free-form SQL, PowerShell, URL, table, executable or credential-value field.

Secret values are never typed into ordinary action forms; actions consume the credential package through approved references.

## 10. Preview is mandatory for mutating/composite APPLY

[PROPOSED] Clicking Preview creates a PREVIEW operation and shows its structured result/plan. The UI does not synthesize a plan client-side.

Before APPLY, the preview page shows:

- exact target(s);
- plan/child fingerprint;
- planned changes and no-change rows;
- blocking errors and warnings separately;
- `BLOCKED_BY`/`NOT_APPLICABLE` rows distinctly;
- restart/outage/destructive effects;
- backup/restore capability and warnings about irreversible effects;
- missing credential **reference names** only;
- plan expiry, if applicable.

An APPLY button is disabled if the backend says the plan is not applicable, stale, blocked or not apply-capable.

## 11. Confirmation before APPLY

[PROPOSED] Confirmation is server-driven from the action contract and binds to the exact fingerprint/operation target.

Flow:

1. operator reviews preview;
2. UI asks for exact confirmation text where the action defines one (for example source specs use `DEPLOY` for FULL_DEPLOYMENT and `COPY` for DATABASE_COPY);
3. UI posts action, targets, fingerprint and confirmation token/text; it does not post a reconstructed plan;
4. backend revalidates all preconditions.

For destructive actions, UI repeats source/destination identities and recovery/safety-backup state adjacent to the confirmation field. A checkbox alone is not a substitute for required typed confirmation.

## 12. Operation progress

Display one operation page keyed by server-generated `OperationId`:

- lifecycle status;
- engine/action/mode/targets;
- start/complete timestamps;
- child steps for composites;
- result counts and current safe stage;
- cancellation availability from coordinator/engine contract;
- non-secret log/result/manifest references.

Polling/events are presentation details; terminal state always comes from the operation coordinator/result, not inferred from absence of progress.

## 13. Idempotent browser behavior

Every mutation request carries a client-generated random idempotency key held in page memory until the request has a definitive operation id. Network retry uses the same key and identical request; it never generates a second key merely because a response was lost.

`IDEMPOTENCY_CONFLICT` is shown as a state mismatch requiring a fresh action, not retried automatically.

Duplicate submit buttons are disabled after acceptance but server idempotency remains authoritative.

## 14. Locks and conflicts

`LOCK_CONFLICT` displays:

- requested action/target;
- conflicting resource category/operation id where safe;
- guidance to open the active operation and wait/cancel only if allowed.

UI offers no “force unlock”. Locks end only through coordinator lifecycle/process rules.

## 15. Cancellation

Show Cancel only when coordinator/engine contract says `COOPERATIVE`. Explain that cancellation can stop at a safe point and does not imply rollback.

For `NONE`, show `Not safely cancellable` and why shutdown may wait. UI never kills child PowerShell/processes directly.

## 16. Controlled shutdown

Closing the browser is not process shutdown.

An explicit `Exit console` control calls controlled shutdown:

- admission closes first;
- cooperative cancellation is requested only according to policy/operator choice;
- if active work blocks exit, display operation ids/actions and keep process running;
- no “force exit” button in V1 coordinator surface.

When `ReadyToExit=true`, the UI can show final confirmation/process-close status.

## 17. Error presentation

Errors are shown by stable category/code plus safe explanation and next action. Never render raw stack traces, SQL exception dumps, HTTP bodies, process command lines containing secrets or arbitrary engine stderr.

Recommended groups:

- package/catalog trust;
- target/model validation;
- missing prerequisite/credential reference;
- plan drift/expiry;
- lock/idempotency conflict;
- operation/child failure;
- backup/restore/recovery required;
- cancellation/shutdown;
- unexpected internal error with operation/log reference.

A copy-details action copies only the redacted structured diagnostic fields.

## 18. Results and severity

UI keeps distinct concepts distinct:

- engine execution `succeeded`;
- per-row severity/status;
- target success/failure counts;
- composite child status;
- warning/info counts.

Do not turn every `ERROR`-severity diagnostic row into a red page without the engine-specific contract; MODEL_REVIEW is a known case where diagnostic findings and execution status need explicit mapping.

## 19. Backup/recovery surface

For operations that changed managed targets, display child/run backup metadata:

- backup created yes/no;
- safe non-secret name/location/reference;
- restore availability and limitations;
- warning if manual recovery is required.

Do not allow opening/downloading secret-bearing backup content through the browser merely because a path is known. Restore is a separately authorized operation/workflow with confirmation and current-state checks.

## 20. Browser security headers/content rules

Product response must retain the accepted Phase 1C controls:

- exact Host/Origin;
- no ACAO/CORS opening;
- restrictive CSP without `unsafe-inline` unless separately reviewed;
- `Cache-Control: no-store`, `Pragma: no-cache`;
- `X-Content-Type-Options: nosniff`;
- no-referrer policy;
- restrictive Permissions-Policy;
- COOP/CORP as proven by the spike.

All operator/catalog strings rendered into HTML are context-escaped. External links use safe target/rel semantics.

## 21. Responsive/accessibility baseline

[PROPOSED] The operator surface remains usable at common server-browser desktop widths; mobile optimization is not an acceptance target. Keyboard navigation, visible focus, semantic labels, non-color-only status cues and accessible confirmation/error text are required.

Large result tables support filtering/paging without dropping rows from the underlying result.

## 22. What the UI does not own

The UI does not:

- verify package signatures independently;
- parse/execute engine scripts;
- decrypt credentials directly;
- modify SQLite/catalog files;
- decide engine safety gates;
- bypass a blocked preflight;
- release locks;
- force-kill mutable engines;
- merge or reseal owner catalog changes;
- infer a successful operation from HTTP 200 alone.

Backend/runtime contracts remain authoritative.

## 23. Required product/browser tests

Before M4.2 acceptance:

- fragment bootstrap is sent once/cleared and never appears in request query/server log;
- no session/CSRF cookie/localStorage/sessionStorage;
- correct session header on protected calls;
- mutation fails for missing/wrong session, Origin or CSRF;
- forged Host/foreign Origin/CORS preflight rejected;
- security headers/CSP/no-store on HTML/API responses where applicable;
- session/logout/restart invalidation;
- complete output capture proves no token leak;
- duplicate click/network retry executes one operation;
- preview required and stale fingerprint blocks APPLY;
- exact confirmation text and destructive summary;
- lock conflict has no force-unlock path;
- cooperative versus non-cancellable operation controls;
- blocked shutdown keeps process alive;
- result/severity distinctions and redacted error display;
- malicious catalog display strings remain encoded;
- browser refresh/bootstrap-loss fails closed/relaunches rather than recovering credentials from storage.

[V] Final elevated-process/browser behavior on a SISQUAL sandbox if required.

## 24. Open decisions

1. [PENDING] Final session lifetime/idle policy.
2. [PENDING] Polling versus local event stream for operation progress; must not weaken security boundary.
3. [PENDING] Exact visual design/branding; this specification fixes behavior/safety, not styling.
4. [PENDING] Final public REST routes/status vocabulary after Phase 3 adoption.

## 25. Entry gate for M4.2

UI implementation may start when:

- Phase 1C V2 session model and operation coordinator are adopted into product runtime or deliberately superseded;
- M1 operator command/result semantics exist for at least preflight;
- action/result schemas expose the fields the UI displays;
- confirmation/cancellation/lock semantics are backend contracts, not UI conventions;
- browser-level security regression tests can run on Windows 2022/2025.
