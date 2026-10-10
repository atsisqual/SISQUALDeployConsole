# ENVIRONMENT_STATE_PROBE port brief

**Status:** [PROPOSED]
**Task:** T11 / M3.7
**Date:** 2026-10-10

This brief defines the implementation gate for `ENVIRONMENT_STATE_PROBE`. It is documentation only.

## 1. Sources and evidence boundary

[CONFIRMED] Checked now against `main`:

- `docs/engines/ENVIRONMENT_STATE_PROBE.md` documents source-era `Invoke-EnvironmentStateProbe.ps1` and action `ENVIRONMENT_STATE_PROBE`.
- The host classification in the engine documentation is `OBSERVATIONAL`: the engine observes managed targets and may produce logs/status artifacts, but does not mutate IIS, databases or applications.
- Catalog inputs are enabled local `dbo.ManagedInstance`/`dbo.ManagedServer` rows plus enabled published `cfg.Application` link metadata.
- ADR-0006 requires PowerShell 7 IIS reads through `Microsoft.Web.Administration`, not the broken WebAdministration provider.

[NOT VERIFIED] The old probe was not run in this brief. Public-name hairpin/DNS/firewall behavior and 21-instance timing remain `[V]` evidence.

## 2. Purpose and class

[CONFIRMED] The probe measures, per enabled instance, database connectivity, IIS site state, published application HTTP health and Web Access/root health, then derives an overall state.

[CONFIRMED] There are no credential references. Requests are unauthenticated.

[PROPOSED] V1 has one observational execution path. The source-era central state-table write does not port because runtime has no central database. A status snapshot file, if retained, is an output artifact rather than a mutation of a managed target.

## 3. Inputs and target scope

For each enabled instance of the local verified catalog:

- instance database target comes from catalog machine/SQL/database fields;
- IIS site identity comes from approved catalog instance/site naming;
- application URLs come only from enabled `cfg.Application` rows that are published and have a non-root IIS path;
- Web Access/root URL comes from the approved instance/public URL model.

[PROPOSED] A caller-supplied URL, SQL target or site name is not accepted as a probe target. Instance filter, if present, must select exactly one enabled local instance.

## 4. Component state rules

[CONFIRMED] Source-era component states are `ONLINE`, `OFFLINE`, `PARTIALLY_ONLINE` and `UNKNOWN` as applicable.

[PROPOSED] Define classifications mechanically:

- **Database:** connection succeeds inside a bounded timeout -> `ONLINE`; known connection/refusal/timeout -> `OFFLINE`; inability to construct/probe safely -> `UNKNOWN`.
- **IIS:** MWA site started -> `ONLINE`; known stopped -> `OFFLINE`; absent/unreadable -> `UNKNOWN` unless source/owner evidence requires a stronger failure.
- **Applications/Web:** shared HTTP classifier: 2xx/3xx healthy; 401/403 count as responding; 404/5xx are not online; timeout/refused/TLS failure are not online. Redirects are bounded and every hop is subject to the same safety policy.
- **Application aggregate:** all online -> `ONLINE`; none online -> `OFFLINE`; mixture -> `PARTIALLY_ONLINE`; none safely checked -> `UNKNOWN`.

[CONFIRMED, source-era defect] A final response on the same host could previously count as online regardless of HTTP status. Do not port that behavior.

## 5. Overall state

[CONFIRMED] Existing source logic makes database/IIS hard gates: either offline makes overall offline; both unknown makes unknown; database+IIS+applications online makes online; otherwise partial.

[PENDING] Web Access was measured but excluded from source overall state. The implementation must either preserve that explicitly or adopt an owner-approved matrix. Do not silently add it to overall health because it seems desirable.

[PROPOSED] Encode the final state matrix as a table-driven test, not nested ad-hoc branches, so every component combination has an expected result.

## 6. HTTP and TLS safety

[CONFIRMED, source-era defect] The old probe disabled TLS certificate validation process-wide.

[PROPOSED] Certificate validation is enabled by default. No carried policy field has been confirmed in this brief for an exception, so V1 does not invent one. If a later owner-approved option is added, scope it to the individual request/target and never process-global state.

Redirect handling must:

- cap hop count;
- preserve a total request deadline;
- reject unsafe schemes;
- not forward credentials (none are expected);
- record only bounded/redacted URL/error information.

## 7. Bounded concurrency and deadline

[CONFIRMED, source-era defect] Sequential 12-application × 10-redirect × 8-second checks can take roughly 16 minutes per instance in the worst case.

[PROPOSED] Use bounded parallelism with one overall engine deadline and per-probe timeouts. Cancellation/deadline must stop scheduling new checks and return structured partial/unknown states for probes not completed, without killing unrelated external processes because none are launched.

Ordering of result rows remains deterministic regardless of completion order.

## 8. Persistence/output

[CONFIRMED] The source APPLY wrote a central state row; that database no longer exists in the portable architecture.

[PROPOSED] The primary output is the engine result. If latest-state persistence is needed, write one bounded status snapshot per instance under the approved log/status root, atomically, with no secrets. The snapshot is disposable observation state and has no restore requirement.

[PENDING] Whether status snapshots are retained at all; recommendation from the existing specification is on-demand probe plus latest status file/log line, not database persistence.

## 9. Side effects and backup

No managed-target writes. Network/SQL connections and IIS reads are observations. Optional status/log files are engine outputs.

Backup/restore is not applicable.

## 10. Failure/result semantics

[PROPOSED] A failed component probe does not abort other component/instance probes. It produces the component state and a bounded reason category (`TIMEOUT`, `REFUSED`, `TLS`, `HTTP_STATUS`, `SITE_NOT_FOUND`, `SQL_CONNECT`, etc.). The engine process fails only for contract/catalog/internal failures that prevent producing a trustworthy structured result, not merely because an environment is unhealthy.

Do not include arbitrary HTTP response bodies or SQL exception payloads in results.

## 11. Required tests

Runner tests must cover:

- LocalDB/SQL online, refusal and timeout;
- MWA site started, stopped and absent;
- local HTTP/HTTPS 200, redirect chain, 401, 403, 404, 500, timeout/refused;
- invalid TLS certificate proves validation remains enabled;
- no process-global TLS-validation change;
- same-host 404/500 are not online (source regression);
- redirect-hop cap and overall deadline;
- bounded parallelism with deterministic row order;
- each application aggregate state;
- complete overall-state matrix, including current Web Access non-participation unless decision changes it;
- all enabled local instances when no filter; exact enabled instance when filtered;
- caller cannot inject URL/site/SQL target;
- cancellation/deadline returns structured partial/unknown observations;
- optional status snapshot is atomic, bounded and contains no response body/secret.

[V] Public-name probing from real servers, hairpin/firewall/DNS effects and timing at the largest machine.

## 12. Open questions

1. [PENDING] Persist latest status file or result/log only.
2. [PENDING] Public-name probe only versus an explicit loopback-with-Host diagnostic mode.
3. [PENDING] Whether Web Access contributes to overall state.
4. [PROPOSED] Share one HTTP classification module with `PULSE_STATUS`; do not copy subtly different status logic.

## 13. Entry gate for the code PR

The code PR may start when:

- target URL/SQL/IIS derivation is catalog-only and tested;
- shared HTTP status/TLS/redirect rules are agreed;
- overall-state matrix including Web Access policy is explicit;
- concurrency/deadline limits are fixed and deterministic tests exist;
- optional persistence location/retention is decided or omitted;
- real-server network behavior remains `[V]`, not claimed from local runner tests.
