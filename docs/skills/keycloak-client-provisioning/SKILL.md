# Skill: keycloak-client-provisioning

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Provision or reconcile SISQUAL Keycloak client configuration using approved engine modules and secret-safe credential delivery.

## Required inputs

- target instance identity;
- approved client definition and URLs;
- credential package reference or secret handle, never secret plaintext in repository content;
- Keycloak reachability and version evidence.

## Safety rules

- Never log or echo client secrets.
- Never copy client secrets from a cloned source environment without explicit target validation.
- Validate target URLs, client identity, and machine ownership before apply.
- Central configuration remains read-only in V1.

## Expected outputs

- current/desired client comparison;
- preview plan;
- apply result from the common engine contract;
- secret-redaction evidence;
- `[V]` checks for real Keycloak topology.

## Dependencies

[PENDING] Final workflow depends on credential-package approval, Keycloak engine ports, and the local operation coordinator.
