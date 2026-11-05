# 0236: Offline chain proofs and sealed evidence bundles

- Status: accepted
- Date: 2026-11-05

## Context

A hash chain only convinces someone who can query the database. A party that
disputes a record, or an auditor, needs to check one row without access.

## Decision

`chain_proof(table, tenant_column, tenant, seq)` returns the rows from `seq` up
to the first signed checkpoint that covers it, each with the exact text its hash
covers (`hashed`), and that checkpoint. `verifyChainProof(proof, jwks)` hashes
that text with the previous hash, checks links and the checkpoint's JWS, using
WebCrypto only (invariant 6). Returning the hashed text avoids reimplementing
Postgres's jsonb text format in TypeScript.

`createChain` (heads, checkpoint, checkpoints, proof, verify) works on any
table tagged `chain`. `evidenceBundle` seals proofs and other JSON sections
with a SHA-256 of the content, and `verifyEvidenceBundle` checks the hash and
every proof.

## Alternatives considered

- Canonicalizing rows in TypeScript. It breaks on numeric and timestamp
  formatting differences.
- Building the bundle inside the audit block. A bundle spans blocks, so the
  app collects the sections and the audit subpath only seals and verifies them.

## Consequences

An auditor needs the bundle and the public keys. A proof ends at a checkpoint,
so rows after the last checkpoint prove integrity only up to the chain head.
Attachment hashes, version hashes and shipment proof are not part of this
change.
