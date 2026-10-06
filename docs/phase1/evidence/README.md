# Phase 1 execution evidence

**Status:** [PROPOSED] evidence-recording convention for Phase 1 spikes.

This directory preserves reproducible evidence for compatibility and security gates. A result is not [CONFIRMED] merely because a workflow was created or queued.

## Required execution ledger

Every recorded workflow execution must identify, when GitHub exposes the value:

- PR number and branch;
- exact commit SHA;
- workflow name and workflow ID;
- run ID and run number;
- event/trigger;
- `run_attempt`;
- each job name and job ID;
- requested runner/OS label;
- runner ID/name when a runner was assigned;
- created, started and completed UTC timestamps;
- job status and conclusion;
- whether any steps actually executed;
- important failed/skipped step names;
- artifact display names and artifact IDs;
- hashes, versions and other values that are part of the gate;
- reason for re-run, cancellation or supersession.

## Attempt semantics

[PROPOSED] A runner/infrastructure retry that does not change code keeps the same run ID and increments `run_attempt`. Every attempt remains in the ledger with its own job IDs.

[PROPOSED] A code or workflow change produces a new commit and a new run ID. The earlier run remains immutable historical evidence and is marked superseded; it is never rewritten as if it had tested the newer code.

[PROPOSED] Cancellation or queue timeout before runner assignment is infrastructure evidence only. It is neither PASS nor FAIL for the technical candidate.

[PROPOSED] A failed technical gate remains recorded even after a fix. The fix points to a new commit/run; the old failure is not removed.

## Acceptance semantics

A spike may claim [CONFIRMED] technical viability only from one explicitly identified accepted `run ID + run_attempt + commit SHA` whose required jobs executed and whose required artifacts were preserved.

The evidence record must distinguish:

- [CONFIRMED] observed result;
- [PROPOSED] architecture or dependency recommendation based on that result;
- [PENDING] owner/reviewer decision or missing execution;
- [V] real SISQUAL/Windows validation that GitHub-hosted runners cannot prove.

## Artifacts

If artifacts are part of the gate, preserve their GitHub artifact IDs as well as names. Copy the relevant text/JSON evidence into the run directory before integration where practical, so later review does not depend only on artifact retention.

Never place credentials, tokens, decrypted secrets, private keys or secret-bearing configuration values in evidence files.
