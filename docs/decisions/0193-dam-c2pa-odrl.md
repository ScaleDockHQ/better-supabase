# 0193: DAM reads C2PA manifests through a port and exports usage rights as ODRL

- Status: accepted
- Date: 2026-11-01

## Context

Provenance and rights exchange need standards, but a C2PA verifier is native code.

## Decision

`readC2paManifest` runs a versioned `C2paReader` port (`apiVersion: 1`) and `damUsageRightsToOdrl` writes an ODRL 2.2 Set. Pins are `c2pa` (2.2) and `odrl` (2.2). Nothing is bundled and no table changes.

## Alternatives considered

Bundling c2pa-node (rejected: native binaries break runtime entries). Importing ODRL (rejected: the table stays the source of truth).

## Consequences

Apps supply a reader. Storing the result needs the app's own columns until a later SQL version.
