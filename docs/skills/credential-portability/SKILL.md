# Skill: credential-portability

**Status:** [PROPOSED] skeleton only. No implementation script exists in Phase 2.

## Purpose

Validate the machine-bound credential-package workflow without exposing secret plaintext or private keys.

## Required inputs

- target machine identity and public-key fingerprint;
- credential-package metadata;
- trusted central signing identity;
- expected server/instance scope.

## Safety rules

- Private machine keys never leave the machine.
- Never log decrypted secret values.
- Validate package signature, target server, key fingerprint, version, expiry, and replay/sequence state before decryption.
- Copying the DeployConsole folder to another machine must not transfer a usable private identity.

## Expected outputs

- machine/public-key identity summary;
- package validation result;
- metadata-only import/use audit;
- negative-test results for wrong machine, tampering, expiry, replay, and wrong fingerprint;
- `[V]` items for the approved Windows environment.

## Dependencies

[PENDING] Final workflow depends on Phase 1B machine-key ADR and the approved credential-package contract.
